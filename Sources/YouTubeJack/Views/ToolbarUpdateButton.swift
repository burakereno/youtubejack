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
                Label("Yeniden başlatılıyor…", systemImage: "arrow.clockwise")
            } else if updater.isDownloading {
                Label("İndiriliyor %\(Int(updater.downloadProgress * 100))", systemImage: "arrow.down.circle")
                    .monospacedDigit()
            } else {
                Label("Güncelle", systemImage: "arrow.down.circle.fill")
            }
        }
        .labelStyle(.titleAndIcon)
        .modifier(NativeProminentButton())
        .buttonBorderShape(.capsule)
        .controlSize(.large)
        .tint(.green)
        .disabled(updater.isDownloading || updater.isInstalling)
        .help(updater.isPreviewingUpdate
              ? "Güncelleme düğmesi önizlemesi; bilgi panelini açar"
              : "YouTubeJack \(updater.latestVersion ?? "") indir ve kur")
    }
}
