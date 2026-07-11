import Foundation
import XCTest
@testable import YouTubeJack

final class UpdateSecurityTests: XCTestCase {
    func testWrongBundleIdentifierIsRejectedBeforeInstall() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: directory) }
        let artifact = directory.appendingPathComponent("YouTubeJack.dmg")
        try Data("abc".utf8).write(to: artifact)
        let manifest = UpdateManifest(
            version: "1.0.0",
            asset: "YouTubeJack.dmg",
            sha256: "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad",
            bundleIdentifier: "dev.local.Impostor",
            teamIdentifier: "66K3EFBVB6"
        )

        XCTAssertThrowsError(
            try UpdateSecurity.verify(
                manifest: manifest,
                artifactURL: artifact,
                expectedVersion: "1.0.0",
                expectedAsset: "YouTubeJack.dmg",
                expectedBundleIdentifier: "dev.local.YouTubeJack"
            )
        ) {
            XCTAssertEqual($0 as? UpdateSecurityError, .bundleIdentifierMismatch)
        }
    }
}
