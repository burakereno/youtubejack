import SwiftUI

struct URLInputBar: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "link")
                .foregroundStyle(.secondary)

            TextField("YouTube linki", text: $model.inputURL)
                .textFieldStyle(.roundedBorder)
                .onSubmit {
                    Task { await model.analyzeCurrentURL() }
                }
                .onChange(of: model.inputURL) {
                    model.scheduleAnalyzeForCurrentURL()
                }

            Button {
                model.clearCurrentInput()
            } label: {
                Label("Temizle", systemImage: "xmark.circle")
            }
            .labelStyle(.iconOnly)
            .disabled(model.inputURL.isEmpty)
            .help("Temizle")
        }
    }
}
