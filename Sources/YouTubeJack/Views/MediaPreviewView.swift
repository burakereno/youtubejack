import SwiftUI
import YouTubeJackCore

struct MediaPreviewView: View {
    let media: MediaInfo

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            ThumbnailView(url: media.thumbnailURL)
                .frame(width: 180, height: 102)

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Label(media.kind == .playlist ? "Playlist" : "Video", systemImage: media.kind == .playlist ? "list.bullet.rectangle" : "play.rectangle")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                    if media.kind == .playlist {
                        Text("\(media.entryCount) video")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else if DisplayFormatters.duration(media.duration).isEmpty == false {
                        Text(DisplayFormatters.duration(media.duration))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Text(media.title)
                    .font(.title3.weight(.semibold))
                    .lineLimit(2)

                if media.creator.isEmpty == false {
                    Text(media.creator)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()
        }
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
    }
}

struct ThumbnailView: View {
    let url: URL?

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6)
                .fill(.quaternary)

            if let url {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    case .failure:
                        Image(systemName: "play.rectangle")
                            .font(.largeTitle)
                            .foregroundStyle(.secondary)
                    case .empty:
                        ProgressView()
                            .controlSize(.small)
                    @unknown default:
                        EmptyView()
                    }
                }
            } else {
                Image(systemName: "play.rectangle")
                    .font(.largeTitle)
                    .foregroundStyle(.secondary)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}
