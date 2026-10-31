import SwiftUI

struct AddToQueueButton: View {
    @EnvironmentObject private var model: AppModel
    var title = "Kuyruğa ekle"

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
        .help("Seçili kalite ve formatla kuyruğa ekle")
    }
}
