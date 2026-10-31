import YouTubeJackCore
import SwiftUI

struct AddToQueueButton: View {
    @EnvironmentObject private var model: AppModel
    var title = L10n.string("Add to queue")

    var body: some View {
        Button {
            model.addSelectedToQueue()
        } label: {
            Label(title, systemImage: "text.badge.plus")
                .font(.callout.weight(.semibold))
                .lineLimit(1)
                .frame(maxWidth: .infinity)
        }
        .modifier(NativeProminentButton())
        .controlSize(.extraLarge)
        .modifier(FlexibleControlSizing())
        .frame(height: AppControlMetrics.height)
        .disabled(model.canAddToQueue == false)
        .help(L10n.string("Add to queue with the selected quality and format"))
    }
}
