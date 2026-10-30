import SwiftUI
import YouTubeJackCore

struct AudioLanguagePickerView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Label("Ses dili", systemImage: "waveform")
                    .font(.headline)
                Spacer(minLength: 12)
                Picker("Ses dili", selection: Binding(
                    get: { model.selectedAudioLanguage },
                    set: { model.updateSelectedAudioLanguage($0) }
                )) {
                    Text(originalTitle).tag(AudioLanguageSelection.original)
                    ForEach(model.audioLanguages.filter { $0.isOriginal == false }) { language in
                        Text(language.title).tag(language.selection)
                    }
                }
                .labelsHidden()
                .frame(maxWidth: 300)
                .disabled(model.isAnalyzingFormats)
                .accessibilityLabel("İndirilecek ses dili")
            }

            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
    }

    private var originalTitle: String {
        AudioLanguageSelection.original.resolved(in: model.media?.formatAvailability ?? .unknown).title
    }

    private var detail: String {
        if model.isAnalyzingFormats { return "Mevcut ses dilleri kontrol ediliyor…" }
        if model.media?.kind == .playlist {
            return "Seçilen ses dili her videoda kontrol edilir. Dil bulunamazsa ilgili indirme kuyrukta belirtilir."
        }
        if model.audioLanguages.filter({ $0.isOriginal == false }).isEmpty {
            return "Bu videoda alternatif ses dili bulunamadı. Orijinal ses indirilecek."
        }
        return "Video, seçtiğiniz ses diliyle indirilir. Altyazı dilini ayrıca seçebilirsiniz."
    }
}
