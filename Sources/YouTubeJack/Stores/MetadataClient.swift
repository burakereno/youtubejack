import YouTubeJackCore

struct MetadataClient: Sendable {
    var fetchPreview: @Sendable (String) async throws -> MetadataResult
    var fetch: @Sendable (String) async throws -> MetadataResult

    init(fetchPreview: @escaping @Sendable (String) async throws -> MetadataResult,
         fetch: @escaping @Sendable (String) async throws -> MetadataResult) {
        self.fetchPreview = fetchPreview
        self.fetch = fetch
    }

    init(service: MetadataService) {
        fetchPreview = { try await service.fetchPreview(url: $0) }
        fetch = { try await service.fetch(url: $0) }
    }
}
