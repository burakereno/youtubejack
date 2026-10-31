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
                    Text(L10n.string("Audio language"))
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

            MenuField(L10n.string("Download audio language"), value: selectedTitle) {
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
        if model.isAnalyzingFormats { return L10n.string("Checking available audio languages…") }
        if model.media?.kind == .playlist {
            if model.playlistAvailability.failedCount > 0 {
                return L10n.string("Showing audio languages from the videos that could be checked. The selected language is checked again for each download.")
            }
            if model.audioLanguages.isEmpty {
                return L10n.string("No alternative audio languages were found in the selected videos. Each video's original audio will be downloaded.")
            }
            return L10n.string("Showing audio languages found in the selected videos. Videos missing the selected language are identified in the queue.")
        }
        if model.audioLanguages.filter({ $0.isOriginal == false }).isEmpty {
            return L10n.string("No alternative audio languages were found in this video. Original audio will be downloaded.")
        }
        return L10n.string("The video is downloaded with your selected audio language. You can choose subtitles separately.")
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
