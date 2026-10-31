import SwiftUI
import YouTubeJackCore

struct SubtitlePickerView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(L10n.string("Subtitles"), systemImage: "captions.bubble")
                    .font(.headline)
                Spacer()
                Toggle(L10n.string("Include subtitles"), isOn: $model.includesSubtitles)
                    .toggleStyle(.switch)
                    .controlSize(.regular)
                    .disabled(model.canIncludeSubtitles == false || model.isAnalyzingFormats)
            }

            if model.selectedQuality.isAudioOnly {
                Text(L10n.string("Subtitles are available for video downloads."))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else if model.isAnalyzingFormats {
                Text(L10n.string("Checking available subtitles…"))
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
                    Text(L10n.string("Save as"))
                        .font(.callout.weight(.semibold))
                    MenuField(L10n.string("Subtitle delivery"), value: model.subtitleOptions.delivery.title) {
                        ForEach(SubtitleDelivery.allCases) { delivery in
                            MenuChoice(title: delivery.title, isSelected: model.subtitleOptions.delivery == delivery) {
                                model.subtitleOptions.delivery = delivery
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(alignment: .leading, spacing: 8) {
                    Text(L10n.string("Languages"))
                        .font(.callout.weight(.semibold))
                    MenuField(L10n.string("Subtitle languages"), value: model.subtitleOptions.languageCodes.isEmpty ? L10n.string("Choose language") : model.subtitleOptions.summary) {
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
            Text(L10n.string("File format"))
                .font(.callout.weight(.semibold))
            MenuField(L10n.string("Subtitle file format"), value: model.subtitleOptions.format.title) {
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
                Toggle(L10n.string("Include automatic captions"), isOn: $model.includesAutomaticSubtitles)
                    .toggleStyle(.checkbox)
                    .font(.callout.weight(.semibold))

                Text(L10n.string("Include captions that YouTube generates using speech recognition or automatic translation. Publisher captions are preferred when available in the same language. Automatic captions may contain errors."))
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
                Text(L10n.string("Only automatic captions are available"))
                    .font(.callout.weight(.semibold))

                Text(model.media?.kind == .playlist
                     ? L10n.string("No publisher captions were found in the selected videos. Enable automatic captions below to use them. Otherwise, the videos will be downloaded without subtitles.")
                     : L10n.string("No publisher captions were found in this video. Enable automatic captions below to use them. Otherwise, the video will be downloaded without subtitles."))
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
        if model.isAnalyzingFormats { return L10n.string("Checking available subtitles…") }
        if model.media?.kind == .playlist {
            if model.playlistAvailability.selectedEntries.isEmpty { return L10n.string("Select playlist videos to see available subtitles.") }
            if model.playlistAvailability.failedCount > 0 {
                return L10n.string("Showing subtitles from the videos that could be checked. Missing subtitles are identified in the queue.")
            }
            if model.subtitleLanguages.isEmpty {
                return L10n.string("No subtitles were found in the selected videos. The videos will be downloaded without subtitles.")
            }
            return L10n.string("Showing languages found in the selected videos. Subtitles are applied to each video separately; missing languages are identified in the queue.")
        }
        if model.subtitleAvailability.isKnown, model.subtitleLanguages.isEmpty {
            return L10n.string("No subtitles were found in this video. It will be downloaded without subtitles.")
        }
        if model.subtitleOptions.languageCodes.isEmpty { return L10n.string("Select at least one subtitle language.") }
        return model.subtitleOptions.delivery == .embedded
            ? L10n.string("Subtitles are embedded in the video and can be turned on or off in your player. No separate file is created.")
            : L10n.string("Selected subtitles are saved alongside the video with their language code.")
    }
}
