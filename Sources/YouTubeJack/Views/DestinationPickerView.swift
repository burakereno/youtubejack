import YouTubeJackCore
import AppKit
import SwiftUI

struct DestinationPickerView: View {
    enum Style: Equatable {
        case card
        case bar
    }

    @AppStorage(AppPreferenceKeys.downloadDirectory) private var downloadDirectory = AppPreferenceDefaults.downloadDirectory
    var style: Style = .card

    var body: some View {
        HStack(spacing: 10) {
            Label(L10n.string("Folder"), systemImage: "folder")
                .font(.headline)

            Text(downloadDirectory)
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer()

            Button {
                chooseDirectory()
            } label: {
                Label(L10n.string("Choose"), systemImage: "folder.badge.plus")
            }
            .buttonStyle(.bordered)
            .controlSize(.extraLarge)
            .frame(height: AppControlMetrics.height)
        }
        .padding(style == .card ? 12 : 0)
        .background {
            if style == .card {
                RoundedRectangle(cornerRadius: AppControlMetrics.cornerRadius)
                    .fill(.thinMaterial)
            }
        }
    }

    private func chooseDirectory() {
        let panel = NSOpenPanel()
        panel.title = L10n.string("Download folder")
        panel.prompt = L10n.string("Choose")
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: downloadDirectory)
        if panel.runModal() == .OK, let url = panel.url {
            downloadDirectory = url.path
            if let bookmark = try? url.bookmarkData(
                options: .withSecurityScope,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            ) {
                UserDefaults.standard.set(bookmark, forKey: AppPreferenceKeys.downloadDirectoryBookmark)
            }
        }
    }
}
