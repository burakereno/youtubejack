import YouTubeJackCore
import SwiftUI

struct ToolbarUpdateButton: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject private var updater = UpdateChecker.shared

    var body: some View {
        Button {
            if updater.isPreviewingUpdate {
                model.presentUpdatePanel()
            } else {
                model.installAppUpdate(using: updater)
            }
        } label: {
            if updater.isInstalling {
                Label(L10n.string("Restarting…"), systemImage: "arrow.clockwise")
            } else if updater.isDownloading {
                Label(L10n.string("Downloading %lld%%", defaultValue: "Downloading \(Int(updater.downloadProgress * 100))%"), systemImage: "arrow.down.circle")
                    .monospacedDigit()
            } else {
                Label(L10n.string("Update"), systemImage: "arrow.down.circle.fill")
            }
        }
        .labelStyle(.titleAndIcon)
        .modifier(NativeProminentButton())
        .buttonBorderShape(.capsule)
        .controlSize(.large)
        .tint(.green)
        .disabled(updater.isDownloading || updater.isInstalling)
        .help(updater.isPreviewingUpdate
              ? L10n.string("Update button preview; opens the info panel")
              : L10n.string("Download and install YouTubeJack %@", defaultValue: "Download and install YouTubeJack \(updater.latestVersion ?? "")"))
    }
}
