import AppKit
import SwiftUI

struct DestinationPickerView: View {
    @AppStorage(AppPreferenceKeys.downloadDirectory) private var downloadDirectory = AppPreferenceDefaults.downloadDirectory

    var body: some View {
        HStack(spacing: 10) {
            Label("Klasör", systemImage: "folder")
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
                Label("Seç", systemImage: "folder.badge.plus")
            }
        }
        .padding(12)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))
    }

    private func chooseDirectory() {
        let panel = NSOpenPanel()
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
