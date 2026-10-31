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
                Toggle("Altyazı ekle", isOn: $model.includesSubtitles)
                    .toggleStyle(.switch)
                    .controlSize(.regular)
                    .disabled(model.canIncludeSubtitles == false || model.isAnalyzingFormats)
            }

            if model.selectedQuality.isAudioOnly {
                Text("Altyazılar video indirmelerinde kullanılabilir.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else if model.isAnalyzingFormats {
                Text("Kullanılabilir altyazılar kontrol ediliyor…")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else if showsAutomaticSubtitleWarning {
                automaticSubtitleWarning
                automaticSubtitleSection
            } else if model.includesSubtitles {
                subtitleControls
            } else {
                Text(detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)

                if hasAutomaticSubtitles {
                    automaticSubtitleSection
                }
            }
        }
        .padding(12)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
    }

    private var subtitleControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Kaydetme biçimi")
                        .font(.callout.weight(.semibold))
                    MenuField("Altyazı kaydetme biçimi", value: model.subtitleOptions.delivery.title) {
                        ForEach(SubtitleDelivery.allCases) { delivery in
                            MenuChoice(title: delivery.title, isSelected: model.subtitleOptions.delivery == delivery) {
                                model.subtitleOptions.delivery = delivery
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Diller")
                        .font(.callout.weight(.semibold))
                    MenuField("Altyazı dilleri", value: model.subtitleOptions.languageCodes.isEmpty ? "Dil seç" : model.subtitleOptions.summary) {
                        ForEach(model.selectableSubtitleLanguages) { language in
                            Toggle(isOn: Binding(
                                get: { model.subtitleOptions.languageCodes.contains(language.code) },
                                set: { model.setSubtitleLanguage(language.code, selected: $0) }
                            )) {
                                Text(languageTitle(language))
                            }
                        }
                    }
                    .disabled(model.isAnalyzingFormats || model.selectableSubtitleLanguages.isEmpty)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if model.subtitleOptions.delivery == .separateFile {
                    subtitleFormatField
                } else {
                    subtitleFormatField.hidden()
                }
            }

            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if hasAutomaticSubtitles {
                automaticSubtitleSection
            }
        }
    }

    private var subtitleFormatField: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Dosya biçimi")
                .font(.callout.weight(.semibold))
            MenuField("Altyazı dosya biçimi", value: model.subtitleOptions.format.title) {
                ForEach(SubtitleFormat.allCases) { format in
                    MenuChoice(title: format.title, isSelected: model.subtitleOptions.format == format) {
                        model.subtitleOptions.format = format
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var automaticSubtitleSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Divider()

            VStack(alignment: .leading, spacing: 6) {
                Toggle("Otomatik altyazıları kullan", isOn: $model.includesAutomaticSubtitles)
                    .toggleStyle(.checkbox)
                    .font(.callout.weight(.semibold))

                Text("YouTube’un konuşmayı tanıyarak oluşturduğu veya otomatik çevirdiği altyazıları listeye ekler. Aynı dilde yayıncı altyazısı varsa ona öncelik verilir. Otomatik metinlerde hata olabilir.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.leading, 22)
            }
        }
        .padding(.top, 4)
        .padding(.bottom, 2)
    }

    private var automaticSubtitleWarning: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text("Yalnızca otomatik altyazı var")
                    .font(.callout.weight(.semibold))

                Text(model.media?.kind == .playlist
                     ? "Seçili videolarda yayıncı tarafından eklenmiş altyazı bulunamadı. Otomatik altyazıları kullanmak için aşağıdaki seçeneği açın. Kapalı kalırsa videolar altyazısız indirilecek."
                     : "Bu videoda yayıncı tarafından eklenmiş altyazı bulunamadı. Otomatik altyazıları kullanmak için aşağıdaki seçeneği açın. Kapalı kalırsa video altyazısız indirilecek.")
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.orange.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(.orange.opacity(0.35), lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
    }

    private var hasAutomaticSubtitles: Bool {
        model.subtitleLanguages.contains(where: \.hasAutomatic)
    }

    private var showsAutomaticSubtitleWarning: Bool {
        model.subtitleOptions.includesAutomatic == false && model.hasOnlyAutomaticSubtitles
    }

    private func languageTitle(_ language: SubtitleLanguage) -> String {
        "\(language.name) · \(language.sourceTitle)"
    }

    private var detail: String {
        if model.isAnalyzingFormats { return "Kullanılabilir altyazılar kontrol ediliyor…" }
        if model.media?.kind == .playlist {
            if model.playlistAvailability.selectedEntries.isEmpty { return "Altyazıları görmek için playlistten video seçin." }
            if model.playlistAvailability.failedCount > 0 {
                return "Kontrol edilebilen videoların altyazıları gösteriliyor. Bulunamayan altyazılar kuyrukta belirtilir."
            }
            if model.subtitleLanguages.isEmpty {
                return "Seçili videolarda altyazı bulunamadı. Videolar altyazısız indirilecek."
            }
            return "Seçili videolarda bulunan diller gösteriliyor. Altyazı her videoya ayrı uygulanır; bulunamayan diller kuyrukta belirtilir."
        }
        if model.subtitleAvailability.isKnown, model.subtitleLanguages.isEmpty {
            return "Bu videoda altyazı bulunamadı. Video altyazısız indirilecek."
        }
        if model.subtitleOptions.languageCodes.isEmpty { return "En az bir altyazı dili seçin." }
        return model.subtitleOptions.delivery == .embedded
            ? "Altyazılar video dosyasına eklenir; oynatıcıda açılıp kapatılabilir. Ayrı dosya oluşturulmaz."
            : "Seçilen altyazılar videoyla aynı klasöre, dil koduyla kaydedilir."
    }
}
