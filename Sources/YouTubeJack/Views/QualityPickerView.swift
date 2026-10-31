import SwiftUI
import YouTubeJackCore

struct QualityPickerView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                DownloadOptionField(L10n.string("Resolution"), value: model.selectedQuality.title) {
                    ForEach(QualityProfile.allCases) { profile in
                        MenuChoice(
                            title: profile.title,
                            isSelected: model.selectedQuality == profile,
                            isAvailable: model.isQualityAvailable(profile)
                        ) {
                            model.updateSelectedQuality(profile)
                        }
                    }
                }

                DownloadOptionField(L10n.string("Video codec"), value: model.selectedQuality.isAudioOnly ? L10n.string("Not applicable") : model.selectedVideoCodec.title) {
                    ForEach(VideoCodecPreference.allCases) { codec in
                        MenuChoice(
                            title: codec.title,
                            isSelected: model.selectedVideoCodec == codec,
                            isAvailable: model.isVideoCodecAvailable(codec)
                        ) {
                            model.updateSelectedVideoCodec(codec)
                        }
                    }
                }
                .disabled(model.selectedQuality.isAudioOnly)

                DownloadOptionField(L10n.string("File format"), value: model.selectedQuality.isAudioOnly ? "M4A" : model.selectedContainer.title) {
                    ForEach(DownloadContainer.allCases) { container in
                        MenuChoice(
                            title: container.title,
                            isSelected: model.selectedContainer == container,
                            isAvailable: model.isContainerAvailable(container, for: model.selectedQuality)
                        ) {
                            model.updateSelectedContainer(container)
                        }
                    }
                }
                .disabled(model.selectedQuality.isAudioOnly)
            }

            if let detail = selectionDetail {
                Text(detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 12)
    }

    private var selectionDetail: String? {
        if model.media?.kind == .playlist { return model.formatSelectionDetail }
        guard model.isAnalyzingFormats == false else { return nil }
        if model.selectedQuality.isAudioOnly
            || model.media?.formatAvailability.isKnown == false
            || model.isQualityAvailable(model.selectedQuality) == false
            || model.isContainerAvailable(model.selectedContainer, for: model.selectedQuality) == false {
            return model.formatSelectionDetail
        }
        return model.maxResolutionDetail
    }
}

private struct DownloadOptionField<Content: View>: View {
    let title: String
    let value: String
    let content: Content

    init(_ title: String, value: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.value = value
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.callout.weight(.semibold))

            MenuField(title, value: value) {
                content
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
