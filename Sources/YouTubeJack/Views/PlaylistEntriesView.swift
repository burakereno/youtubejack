import SwiftUI
import YouTubeJackCore

struct PlaylistEntriesView: View {
    @EnvironmentObject private var model: AppModel

    private var selectedCount: Int {
        model.playlistEntries.filter(\.isSelected).count
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            Divider()

            if model.playlistEntries.isEmpty {
                ContentUnavailableView(L10n.string("Playlist is empty"), systemImage: "list.bullet.rectangle")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                playlistList
            }

            Divider()

            AddToQueueButton(title: L10n.string("Add %lld videos to queue", defaultValue: "Add \(selectedCount) videos to queue"))
                .padding(16)
                .background(.bar)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(L10n.string("Playlist videos"))
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Playlist", systemImage: "list.bullet.rectangle")
                    .font(.headline)

                Spacer(minLength: 8)

                Text(L10n.string("%lld / %lld selected", defaultValue: "\(selectedCount) / \(model.playlistEntries.count) selected"))
                    .font(.callout)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }

            if let title = model.media?.title {
                Text(title)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .help(title)
            }

            HStack(spacing: 12) {
                Button {
                    model.setAllPlaylistEntries(true)
                } label: {
                    Label(L10n.string("Select All"), systemImage: "checklist.checked")
                }
                .frame(maxWidth: .infinity)
                .disabled(selectedCount == model.playlistEntries.count)

                Button {
                    model.setAllPlaylistEntries(false)
                } label: {
                    Label(L10n.string("Deselect All"), systemImage: "checklist.unchecked")
                }
                .frame(maxWidth: .infinity)
                .disabled(selectedCount == 0)
            }
            .buttonStyle(.bordered)
            .controlSize(.regular)
        }
        .padding(16)
        .background(.bar)
    }

    private var playlistList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach($model.playlistEntries) { $entry in
                    VStack(spacing: 0) {
                        PlaylistEntryRow(entry: $entry)

                        if entry.id != model.playlistEntries.last?.id {
                            Divider()
                                .padding(.leading, 156)
                        }
                    }
                }
            }
            .padding(.vertical, 6)
        }
        .scrollIndicators(.visible)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct PlaylistEntryRow: View {
    @Binding var entry: PlaylistEntry

    var body: some View {
        Button {
            entry.isSelected.toggle()
        } label: {
            rowContent
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(entry.isSelected ? Color.accentColor.opacity(0.06) : Color.clear)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(entry.index). \(entry.title)")
        .accessibilityValue(entry.isSelected ? L10n.string("Selected") : L10n.string("Not selected"))
        .accessibilityAddTraits(entry.isSelected ? .isSelected : [])
        .help(entry.isSelected ? L10n.string("Deselect") : L10n.string("Select video"))
    }

    private var rowContent: some View {
        HStack(spacing: 10) {
            Image(systemName: entry.isSelected ? "checkmark.square.fill" : "square")
                .font(.system(size: 16))
                .foregroundStyle(entry.isSelected ? Color.accentColor : Color.secondary)
                .frame(width: 16)
                .accessibilityHidden(true)

            Text("\(entry.index)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 24, alignment: .trailing)

            ThumbnailView(url: entry.thumbnailURL)
                .frame(width: 72, height: 42)

            VStack(alignment: .leading, spacing: 3) {
                Text(entry.title)
                    .lineLimit(2)
                    .help(entry.title)

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
                .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
