import SwiftUI
import YouTubeJackCore

struct PlaylistEntriesView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                let selectedCount = model.playlistEntries.filter(\.isSelected).count

                Text("Playlist")
                    .font(.headline)

                Text("\(selectedCount) seçili")
                    .foregroundStyle(.secondary)

                Spacer()

                Button {
                    model.setAllPlaylistEntries(true)
                } label: {
                    Label("Tümünü Seç", systemImage: "checklist.checked")
                }
                .disabled(selectedCount == model.playlistEntries.count)

                Button {
                    model.setAllPlaylistEntries(false)
                } label: {
                    Label("Seçimi Kaldır", systemImage: "checklist.unchecked")
                }
                .disabled(selectedCount == 0)
            }

            playlistList
        }
    }

    private var playlistList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach($model.playlistEntries) { $entry in
                    PlaylistEntryRow(entry: $entry)

                    if entry.id != model.playlistEntries.last?.id {
                        Divider()
                            .padding(.leading, 104)
                    }
                }
            }
            .padding(.vertical, 6)
        }
        .scrollIndicators(.visible)
        .frame(minHeight: 180, maxHeight: 280)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.secondary.opacity(0.22), lineWidth: 1)
        )
        .overlay(alignment: .bottom) {
            if model.playlistEntries.count > 3 {
                LinearGradient(
                    colors: [.clear, Color.black.opacity(0.18)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 34)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .allowsHitTesting(false)
            }
        }
        .overlay(alignment: .trailing) {
            if model.playlistEntries.count > 3 {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.secondary.opacity(0.42))
                    .frame(width: 4, height: 54)
                    .padding(.trailing, 4)
                    .allowsHitTesting(false)
            }
        }
    }
}

private struct PlaylistEntryRow: View {
    @Binding var entry: PlaylistEntry

    var body: some View {
        HStack(spacing: 10) {
            Toggle("", isOn: $entry.isSelected)
                .labelsHidden()

            Text("\(entry.index)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 32, alignment: .trailing)

            ThumbnailView(url: entry.thumbnailURL)
                .frame(width: 72, height: 42)

            VStack(alignment: .leading, spacing: 3) {
                Text(entry.title)
                    .lineLimit(1)

                HStack(spacing: 8) {
                    if entry.creator.isEmpty == false {
                        Text(entry.creator)
                    }
                    if DisplayFormatters.duration(entry.duration).isEmpty == false {
                        Text(DisplayFormatters.duration(entry.duration))
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}
