import SwiftUI
import YouTubeJackCore

struct ToolbarYTDLPUpdateButton: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        Button {
            model.presentUpdatePanel()
            Task { await model.updateYTDLP() }
        } label: {
            if model.isInstallingYTDLP {
                Label(L10n.string("Updating yt-dlp…"), systemImage: "arrow.down.circle")
            } else {
                Label(L10n.string("Update yt-dlp"), systemImage: "arrow.down.circle.fill")
            }
        }
        .modifier(ToolbarUpdateButtonStyle())
        .disabled(model.canUpdateYTDLP == false)
        .help(L10n.string("Download and install yt-dlp %@", defaultValue: "Download and install yt-dlp \(model.ytdlpLatestVersion ?? "")"))
    }
}
