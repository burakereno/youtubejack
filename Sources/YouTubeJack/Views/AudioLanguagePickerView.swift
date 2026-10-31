import SwiftUI
import YouTubeJackCore

struct AudioLanguagePickerView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        AudioLanguageRowLayout() {
            HStack(alignment: .center, spacing: 16) {
                Image(systemName: "waveform")
                    .font(.headline)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Ses dili")
                        .font(.headline)

                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                        .help(detail)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            MenuField("İndirilecek ses dili", value: selectedTitle) {
                MenuChoice(title: originalTitle, isSelected: model.selectedAudioLanguage == .original) {
                    model.updateSelectedAudioLanguage(.original)
                }
                ForEach(model.audioLanguages.filter { $0.isOriginal == false }) { language in
                    MenuChoice(title: language.title, isSelected: model.selectedAudioLanguage == language.selection) {
                        model.updateSelectedAudioLanguage(language.selection)
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .disabled(model.isAnalyzingFormats || model.audioLanguages.allSatisfy(\.isOriginal))
        }
        .padding(12)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
    }

    private var originalTitle: String {
        AudioLanguageSelection.original.resolved(in: model.media?.formatAvailability ?? .unknown).title
    }

    private var selectedTitle: String {
        model.selectedAudioLanguage.resolved(in: model.media?.formatAvailability ?? .unknown).title
    }

    private var detail: String {
        if model.isAnalyzingFormats { return "Mevcut ses dilleri kontrol ediliyor…" }
        if model.media?.kind == .playlist {
            if model.playlistAvailability.failedCount > 0 {
                return "Kontrol edilebilen videoların ses dilleri gösteriliyor. Seçilen dil her indirmede tekrar kontrol edilir."
            }
            if model.audioLanguages.isEmpty {
                return "Seçili videolarda alternatif ses dili bulunamadı. Her videonun orijinal sesi indirilecek."
            }
            return "Seçili videolarda bulunan ses dilleri gösteriliyor. Seçilen dilin olmadığı videolar kuyrukta belirtilir."
        }
        if model.audioLanguages.filter({ $0.isOriginal == false }).isEmpty {
            return "Bu videoda alternatif ses dili bulunamadı. Orijinal ses indirilecek."
        }
        return "Video, seçtiğiniz ses diliyle indirilir. Altyazı dilini ayrıca seçebilirsiniz."
    }
}

private struct AudioLanguageRowLayout: Layout {
    private let spacing: CGFloat = 12

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard subviews.count == 2 else { return .zero }
        let proposedWidth = proposal.width ?? .infinity
        let width = proposedWidth.isFinite ? proposedWidth : subviews[1].sizeThatFits(.unspecified).width * 3 + spacing * 2
        let fieldWidth = max(0, (width - spacing * 2) / 3)
        let descriptionWidth = max(0, width - fieldWidth - spacing)
        let descriptionSize = subviews[0].sizeThatFits(ProposedViewSize(width: descriptionWidth, height: nil))
        let fieldSize = subviews[1].sizeThatFits(ProposedViewSize(width: fieldWidth, height: nil))
        return CGSize(width: width, height: max(descriptionSize.height, fieldSize.height))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard subviews.count == 2 else { return }
        let fieldWidth = max(0, (bounds.width - spacing * 2) / 3)
        let descriptionWidth = max(0, bounds.width - fieldWidth - spacing)
        subviews[0].place(
            at: CGPoint(x: bounds.minX, y: bounds.midY), anchor: .leading,
            proposal: ProposedViewSize(width: descriptionWidth, height: nil)
        )
        subviews[1].place(
            at: CGPoint(x: bounds.maxX - fieldWidth, y: bounds.midY), anchor: .leading,
            proposal: ProposedViewSize(width: fieldWidth, height: nil)
        )
    }
}
