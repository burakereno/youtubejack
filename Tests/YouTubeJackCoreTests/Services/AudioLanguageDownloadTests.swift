import Foundation
import Testing
@testable import YouTubeJackCore

struct AudioLanguageDownloadTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["YOUTUBEJACK_TEST_INFO_JSON"] != nil), arguments: ["tr", "en", "original"], DownloadContainer.allCases)
    func realYTDLPSelectsExactLanguageFromLiveMetadata(code: String, container: DownloadContainer) async throws {
        let ytdlp = try #require(ProcessInfo.processInfo.environment["YOUTUBEJACK_TEST_YTDLP"])
        let metadata = try #require(ProcessInfo.processInfo.environment["YOUTUBEJACK_TEST_INFO_JSON"])
        let selection = code == "original" ? AudioLanguageSelection.original : AudioLanguageSelection(languageCode: code)
        let selector = QualityProfile.q480.formatSelector(container: container, audioLanguage: selection)
        let result = try await ProcessRunner().run(executablePath: ytdlp, arguments: [
            "--ignore-config", "--load-info-json", metadata, "--simulate", "--no-warnings", "-f", selector,
            "--print", "%(requested_formats.-1.language,language|NA)s"
        ])
        #expect(result.stdout.trimmingCharacters(in: .whitespacesAndNewlines) == (code == "original" ? "fr" : code))
    }

    @Test func metadataPreservesOriginalAndAlternateAudioLanguages() async throws {
        let fixture = try AudioDownloadFixture(mode: "metadata")
        defer { fixture.clean() }
        let result = try await MetadataService(dependencyResolver: fixture.resolver).fetch(url: fixture.url)
        #expect(result.media.formatAvailability.audioLanguages.map(\.code) == ["tr", "en", "fr"])
        #expect(result.media.formatAvailability.originalAudioLanguageCode == "fr")
    }

    @Test func forbiddenAndContainerRetriesKeepRequestedLanguage() async throws {
        let fixture = try AudioDownloadFixture(mode: "retry")
        defer { fixture.clean() }
        var selected: SelectedMediaFormat?
        let path = try await DownloadService(dependencyResolver: fixture.resolver).download(
            item: fixture.item, outputDirectory: fixture.root.path, onProgress: { _ in }, onOutputPath: { _ in },
            onSelectedMediaFormat: { selected = $0 }
        )
        #expect(path == fixture.root.appendingPathComponent("dubbed.webm").path)
        #expect(selected?.audioLanguageCode == "tr")
        let invocations = try String(contentsOf: fixture.root.appendingPathComponent("calls"))
        #expect(invocations.components(separatedBy: "---\n").filter { $0.isEmpty == false }.count == 3)
        for call in invocations.components(separatedBy: "---\n") where call.isEmpty == false {
            #expect(call.contains("[language=tr]"))
            #expect(call.contains(" [tr].%(ext)s"))
        }
    }

    @Test func unavailableLanguageReportsReadableFailureWithoutAnotherLanguageFallback() async throws {
        let fixture = try AudioDownloadFixture(mode: "unavailable")
        defer { fixture.clean() }
        do {
            _ = try await DownloadService(dependencyResolver: fixture.resolver).download(item: fixture.item, outputDirectory: fixture.root.path, onProgress: { _ in }, onOutputPath: { _ in })
            Issue.record("A missing requested dub must not report a completed original-language download.")
        } catch {
            #expect(error.localizedDescription.contains("Türkçe"))
            #expect(error.localizedDescription.contains("bulunamadı"))
        }
        let calls = try String(contentsOf: fixture.root.appendingPathComponent("calls"))
        for call in calls.components(separatedBy: "---\n") where call.isEmpty == false { #expect(call.contains("[language=tr]")) }
    }

    @Test func originalAndTranslatedDownloadsHaveDistinctOutputTemplates() async throws {
        let fixture = try AudioDownloadFixture(mode: "success")
        defer { fixture.clean() }
        let original = DownloadItem(url: fixture.url, title: "Video", quality: .q1080, container: .mp4, audioLanguage: AudioLanguageSelection(languageCode: "fr", isOriginal: true))
        _ = try await DownloadService(dependencyResolver: fixture.resolver).download(item: original, outputDirectory: fixture.root.path, onProgress: { _ in }, onOutputPath: { _ in })
        let calls = try String(contentsOf: fixture.root.appendingPathComponent("calls"))
        #expect(calls.contains("[language=fr]"))
        #expect(calls.contains("%(title).200B.%(ext)s"))
        #expect(calls.contains(" [fr].%(ext)s") == false)
    }
}

private struct AudioDownloadFixture {
    let root: URL
    let url = "https://www.youtube.com/watch?v=CpkM0qAkBNY"
    var resolver: DependencyResolver { DependencyResolver(managedBinDirectory: root, bundledBinDirectory: nil, systemSearchPaths: []) }
    var item: DownloadItem { DownloadItem(url: url, title: "Video", quality: .q1080, container: .mp4, audioLanguage: AudioLanguageSelection(languageCode: "tr")) }

    init(mode: String) throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("audio-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let executable = root.appendingPathComponent("yt-dlp")
        let script = """
        #!/bin/sh
        root="$(dirname "$0")"
        printf '%s\\n' "$@" >> "$root/calls"
        printf '%s\\n' '---' >> "$root/calls"
        if [ '\(mode)' = metadata ]; then
          printf '%s\\n' '{"language":"en","formats":[{"format_id":"fr","ext":"m4a","acodec":"mp4a","vcodec":"none","language":"fr","language_preference":10,"format_note":"French original"},{"format_id":"en","ext":"m4a","acodec":"mp4a","vcodec":"none","language":"en","language_preference":5},{"format_id":"tr","ext":"m4a","acodec":"mp4a","vcodec":"none","language":"tr"}]}'
          exit 0
        fi
        if [ '\(mode)' = unavailable ]; then printf 'ERROR: Requested format is not available\\n' >&2; exit 1; fi
        if [ '\(mode)' = retry ]; then
          chunked=0
          webm=0
          for argument in "$@"; do
            case "$argument" in
              --http-chunk-size) chunked=1 ;;
              *'ext=webm'*) webm=1 ;;
            esac
          done
          if [ "$webm" -eq 0 ]; then
            if [ "$chunked" -eq 0 ]; then printf 'HTTP Error 403: Forbidden\\n' >&2
            else printf 'Requested format is not available\\n' >&2; fi
            exit 1
          fi
        fi
        printf 'download-codecs:1080|vp9|opus|tr\\n'
        printf 'download-output:%s/dubbed.webm\\n' "$root"
        """
        try script.write(to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
    }

    func clean() { try? FileManager.default.removeItem(at: root) }
}
