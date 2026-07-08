import Foundation

public struct DownloadArtifactCleaner: Sendable {
    public init() {}

    public func removeArtifacts(for outputPaths: [String]) {
        let uniquePaths = Set(outputPaths.filter { $0.isEmpty == false })
        for path in uniquePaths {
            for candidate in artifactCandidates(forOutputPath: path) {
                try? FileManager.default.removeItem(at: candidate)
            }
        }
    }

    public func artifactCandidates(forOutputPath path: String) -> [URL] {
        let outputURL = URL(fileURLWithPath: path)
        let directory = outputURL.deletingLastPathComponent()
        let fileName = outputURL.lastPathComponent
        let exactCandidateNames = Set([
            fileName,
            "\(fileName).part",
            "\(fileName).ytdl",
            "\(fileName).temp"
        ])

        var candidates = exactCandidateNames.map { directory.appendingPathComponent($0) }

        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        ) else {
            return candidates
        }

        for candidate in contents {
            let name = candidate.lastPathComponent
            let isYTDLPFragment = name.hasPrefix("\(fileName).part")
            let isYTDLPSidecar = name == "\(fileName).ytdl"
            let isYTDLPTemp = name == "\(fileName).temp"
            if isYTDLPFragment || isYTDLPSidecar || isYTDLPTemp {
                candidates.append(candidate)
            }
        }

        return Array(Set(candidates))
    }
}
