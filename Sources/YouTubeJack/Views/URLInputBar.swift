import SwiftUI

struct URLInputBar: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "link")
                .font(.body.weight(.medium))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            NativeURLInputField(text: $model.inputURL) {
                Task { await model.analyzeCurrentURL() }
            }
            .frame(height: NativeURLInputField.height)
            .onChange(of: model.inputURL) {
                model.scheduleAnalyzeForCurrentURL()
            }

            Button {
                model.clearCurrentInput()
            } label: {
                Label("Temizle", systemImage: "xmark")
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.circle)
            .controlSize(.extraLarge)
            .labelStyle(.iconOnly)
            .modifier(FlexibleControlSizing())
            .frame(width: AppControlMetrics.height, height: AppControlMetrics.height)
            .disabled(model.inputURL.isEmpty)
            .help("Temizle")
        }
    }
}
