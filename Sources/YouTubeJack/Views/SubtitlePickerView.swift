import SwiftUI
import YouTubeJackCore

struct SubtitlePickerView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Altyazı", systemImage: "captions.bubble")
                    .font(.headline)
                Spacer()
                Toggle("Altyazı ekle", isOn: $model.subtitleOptions.isEnabled)
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .disabled(model.selectedQuality.isAudioOnly)
            }

            if model.selectedQuality.isAudioOnly {
                Text("Altyazılar video indirmelerinde kullanılabilir.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else if model.subtitleOptions.isEnabled {
                subtitleControls
            }
        }
        .padding(12)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
    }

    private var subtitleControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker("Kaydetme", selection: $model.subtitleOptions.delivery) {
                ForEach(SubtitleDelivery.allCases) { delivery in
                    Text(delivery.title).tag(delivery)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .accessibilityLabel("Altyazıyı kaydetme biçimi")

            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text("Diller")
                    .font(.callout.weight(.semibold))
                Menu {
                    ForEach(model.subtitleLanguages) { language in
                        Toggle(isOn: Binding(
                            get: { model.subtitleOptions.languageCodes.contains(language.code) },
                            set: { model.setSubtitleLanguage(language.code, selected: $0) }
                        )) {
                            Text(languageTitle(language))
                        }
                        .disabled(language.hasAutomatic && language.hasManual == false && model.subtitleOptions.includesAutomatic == false)
                    }
                } label: {
                    Text(model.subtitleOptions.languageCodes.isEmpty ? "Dil seç" : model.subtitleOptions.summary)
                        .lineLimit(1)
                }
                .disabled(model.isAnalyzingFormats || model.subtitleLanguages.isEmpty)
                .accessibilityLabel("Altyazı dilleri")

                if model.subtitleOptions.delivery == .separateFile {
                    Picker("Biçim", selection: $model.subtitleOptions.format) {
                        ForEach(SubtitleFormat.allCases) { format in
                            Text(format.title).tag(format)
                        }
                    }
                    .fixedSize()
                }
            }

            Toggle("Yayıncı altyazısı yoksa otomatik altyazıyı kullan", isOn: $model.subtitleOptions.includesAutomatic)
                .font(.callout)
                .onChange(of: model.subtitleOptions.includesAutomatic) { _, _ in
                    model.reconcileSubtitleSelection()
                }

            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func languageTitle(_ language: SubtitleLanguage) -> String {
        model.media?.kind == .playlist ? language.name : "\(language.name) · \(language.sourceTitle)"
    }

    private var detail: String {
        if model.isAnalyzingFormats { return "Kullanılabilir altyazılar kontrol ediliyor…" }
        if model.media?.kind == .playlist {
            return "Seçilen diller her videoda ayrı kontrol edilir. Bulunamayan altyazılar kuyrukta belirtilir."
        }
        if model.media?.subtitleAvailability.isKnown == true, model.subtitleLanguages.isEmpty {
            return "Bu videoda altyazı bulunamadı. Video altyazısız indirilecek."
        }
        if model.subtitleOptions.languageCodes.isEmpty { return "En az bir altyazı dili seçin." }
        return model.subtitleOptions.delivery == .embedded
            ? "Altyazılar video dosyasına eklenir; oynatıcıda açılıp kapatılabilir. Ayrı dosya oluşturulmaz."
            : "Seçilen altyazılar videoyla aynı klasöre, dil koduyla kaydedilir."
    }
}
