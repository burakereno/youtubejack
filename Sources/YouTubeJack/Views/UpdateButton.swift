import SwiftUI

struct UpdateButton: View {
    @EnvironmentObject private var model: AppModel
    let version: String
    @ObservedObject private var updater = UpdateChecker.shared

    var body: some View {
        Button {
            model.installAppUpdate(using: updater)
        } label: {
            HStack(spacing: 6) {
                if updater.isInstalling {
                    Text("Yeniden başlatılıyor…")
                } else if updater.isDownloading {
                    Image(systemName: "arrow.down.circle")
                    Text("\(Int(updater.downloadProgress * 100))%")
                        .font(.callout.monospacedDigit().weight(.semibold))
                } else {
                    Image(systemName: "arrow.down.circle.fill")
                    Text("Güncelle")
                }
            }
            .lineLimit(1)
            .frame(maxWidth: .infinity)
        }
        .modifier(NativeProminentButton())
        .buttonBorderShape(.capsule)
        .controlSize(.large)
        .modifier(FlexibleControlSizing())
        .frame(height: AppControlMetrics.height)
        .disabled(updater.isDownloading || updater.isInstalling)
        .help(updater.isDownloading ? "Güncelleme indiriliyor" : "YouTubeJack \(version) indir ve kur")
    }
}
