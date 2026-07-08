import AppKit
import SwiftUI

struct UpdateButton: View {
    let version: String
    @ObservedObject private var updater = UpdateChecker.shared

    var body: some View {
        Button {
            updater.downloadAndInstall()
        } label: {
            HStack(spacing: 6) {
                if updater.isDownloading {
                    Image(systemName: "arrow.down.circle")
                    Text("\(Int(updater.downloadProgress * 100))%")
                        .font(.callout.monospacedDigit().weight(.semibold))
                } else {
                    Image(systemName: "arrow.down.circle.fill")
                    Text("Güncelle \(version)")
                }
            }
            .font(.callout.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .frame(height: 32)
            .background(Color.green, in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .disabled(updater.isDownloading)
        .onHover { hovering in
            if hovering && updater.isDownloading == false {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
            }
        }
        .help(updater.isDownloading ? "Güncelleme indiriliyor" : "YouTubeJack \(version) indir ve kur")
    }
}
