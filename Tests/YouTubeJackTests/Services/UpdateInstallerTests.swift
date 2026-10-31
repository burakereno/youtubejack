import Darwin
import Foundation
import Testing
import YouTubeJackCore
@testable import YouTubeJack

struct UpdateInstallerTests {
    @Test(.timeLimit(.minutes(1)), arguments: ["valid", "noack", "wrongtoken", "wrongversion", "earlyexit"])
    func installerConfirmsTheNewProcessOrRestoresThePreviousApp(mode: String) async throws {
        let fixture = try await InstallerFixture(mode: mode)
        defer { fixture.clean() }
        var exitCode: Int32 = 0
        do {
            _ = try await ProcessRunner().run(executablePath: "/bin/bash", arguments: fixture.arguments, timeout: 15)
        } catch let error as ProcessExecutionError {
            exitCode = error.exitCode
        }
        let log = (try? String(contentsOf: fixture.work.appendingPathComponent("install.log"))) ?? "installer completed"
        #expect(exitCode == (mode == "valid" ? 0 : 1), "Installer log: \(log)")
        #expect(try String(contentsOf: fixture.target.appendingPathComponent("marker")) == (mode == "valid" ? "new" : "old"))
        let info = try PropertyListSerialization.propertyList(from: Data(contentsOf: fixture.target.appendingPathComponent("Contents/Info.plist")), format: nil) as? [String: String]
        #expect(info?["CFBundleShortVersionString"] == (mode == "valid" ? "1.1.0" : "1.0.0"))
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: fixture.root.path)
        #expect(leftovers.contains(where: { $0.hasPrefix(".AuditUpdate.previous.") || $0.hasPrefix(".AuditUpdate.update.") }) == false)
    }
}

private struct InstallerFixture {
    let root: URL
    let work: URL
    let target: URL
    let arguments: [String]
    let otherCopy: Process?

    init(mode: String) async throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("youtubejack-installer-\(UUID().uuidString) with spaces")
        work = root.appendingPathComponent("work")
        target = root.appendingPathComponent("Installed App's.app")
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        let source = root.appendingPathComponent("source/Audit App.app")
        let program = root.appendingPathComponent("helper.c")
        try Self.helperSource.write(to: program, atomically: true, encoding: .utf8)
        let binary = root.appendingPathComponent("AuditUpdate")
        _ = try await ProcessRunner().run(executablePath: "/usr/bin/clang", arguments: [program.path, "-o", binary.path])
        for (app, version, marker) in [(target, "1.0.0", "old"), (source, "1.1.0", "new")] {
            let contents = app.appendingPathComponent("Contents")
            try FileManager.default.createDirectory(at: contents.appendingPathComponent("MacOS"), withIntermediateDirectories: true)
            try FileManager.default.copyItem(at: binary, to: contents.appendingPathComponent("MacOS/AuditUpdate"))
            try PropertyListSerialization.data(fromPropertyList: ["CFBundleIdentifier": "dev.local.YouTubeJack", "CFBundleShortVersionString": version], format: .xml, options: 0)
                .write(to: contents.appendingPathComponent("Info.plist"))
            try marker.write(to: app.appendingPathComponent("marker"), atomically: true, encoding: .utf8)
        }
        let codesign = root.appendingPathComponent("fake-codesign")
        try Self.executable(codesign, "#!/bin/sh\necho 'TeamIdentifier=66K3EFBVB6' >&2\nexit 0\n")
        let spctl = root.appendingPathComponent("fake-spctl")
        try Self.executable(spctl, "#!/bin/sh\nexit 0\n")
        let hdiutil = root.appendingPathComponent("fake-hdiutil")
        try Self.executable(hdiutil, """
        #!/bin/sh
        if [ "$1" = attach ]; then
          while [ "$#" -gt 0 ]; do
            if [ "$1" = -mountpoint ]; then shift; mount="$1"; fi
            shift
          done
          /usr/bin/ditto \(Self.quote(source.path)) "$mount/Audit App.app"
        fi
        exit 0
        """)
        let open = root.appendingPathComponent("fake-open")
        try Self.executable(open, """
        #!/bin/sh
        if [ "$1" = -n ]; then shift; fi
        target="$1"; shift
        if [ "${1:-}" = --args ]; then shift; fi
        AUDIT_MODE=\(Self.quote(mode)) "$target/Contents/MacOS/AuditUpdate" "$@" >/dev/null 2>&1 &
        echo $! >> \(Self.quote(root.appendingPathComponent("launched-pids").path))
        exit 0
        """)
        var script = UpdateSecurity.installerScript
        // Only this temporary test copy substitutes trust/UI tools. Production has no bypass flag.
        for (original, replacement) in [("/usr/bin/codesign", codesign), ("/usr/sbin/spctl", spctl), ("/usr/bin/hdiutil", hdiutil), ("/usr/bin/open", open)] {
            script = script.replacingOccurrences(of: original, with: Self.quote(replacement.path))
        }
        script = script.replacingOccurrences(of: "/usr/bin/seq 1 100", with: "/usr/bin/seq 1 10")
        script = script.replacingOccurrences(of: "/usr/bin/seq 1 20", with: "/usr/bin/seq 1 5")
        let installer = work.appendingPathComponent("installer.sh")
        try script.write(to: installer, atomically: true, encoding: .utf8)
        let artifact = work.appendingPathComponent("YouTubeJack.dmg")
        try Data("fixture signed image".utf8).write(to: artifact)
        arguments = [installer.path, "2147483647", artifact.path, target.path, "dev.local.YouTubeJack", "1.1.0", "Audit App.app", "AuditUpdate", "66K3EFBVB6", try UpdateSecurity.sha256(of: artifact), work.path, work.appendingPathComponent(UpdateLaunchConfirmation.fileName).path, UUID().uuidString]
        if mode == "noack" {
            let other = root.appendingPathComponent("other/AuditUpdate")
            try FileManager.default.createDirectory(at: other.deletingLastPathComponent(), withIntermediateDirectories: true)
            try FileManager.default.copyItem(at: binary, to: other)
            let process = Process()
            process.executableURL = other
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            try process.run()
            otherCopy = process
        } else { otherCopy = nil }
    }

    func clean() {
        if otherCopy?.isRunning == true { otherCopy?.terminate() }
        if let pids = try? String(contentsOf: root.appendingPathComponent("launched-pids")) {
            for line in pids.split(separator: "\n") {
                if let pid = Int32(line), pid > 1 { kill(pid, SIGTERM) }
            }
        }
        try? FileManager.default.removeItem(at: root)
    }

    private static func quote(_ value: String) -> String { "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'" }
    private static func executable(_ url: URL, _ script: String) throws {
        try script.write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
    }

    private static let helperSource = #"""
    #include <stdio.h>
    #include <stdlib.h>
    #include <string.h>
    #include <unistd.h>
    int main(int argc, char **argv) {
        const char *file = NULL, *token = NULL, *version = NULL;
        const char *mode = getenv("AUDIT_MODE");
        if (!mode) mode = "noack";
        for (int i = 1; i + 1 < argc; i++) {
            if (!strcmp(argv[i], "--update-confirmation")) file = argv[++i];
            else if (!strcmp(argv[i], "--update-token")) token = argv[++i];
            else if (!strcmp(argv[i], "--update-version")) version = argv[++i];
        }
        if (file && token && version && strcmp(mode, "noack")) {
            char bundle[4096];
            snprintf(bundle, sizeof(bundle), "%s", argv[0]);
            char *suffix = strstr(bundle, "/Contents/MacOS/");
            if (suffix) *suffix = 0;
            FILE *out = fopen(file, "w");
            if (!out) return 2;
            fprintf(out, "<?xml version=\"1.0\"?><plist version=\"1.0\"><dict><key>token</key><string>%s</string><key>version</key><string>%s</string><key>bundlePath</key><string>%s</string><key>processID</key><integer>%d</integer></dict></plist>",
                    !strcmp(mode, "wrongtoken") ? "wrong" : token,
                    !strcmp(mode, "wrongversion") ? "9.9.9" : version, bundle, getpid());
            fclose(out);
            if (!strcmp(mode, "earlyexit")) { usleep(300000); return 0; }
        }
        sleep(10);
        return 0;
    }
    """#
}
