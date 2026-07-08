import SwiftUI
import YouTubeJackCore

struct QualityPickerView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text("Çözünürlük")
                    .font(.headline)

                if let detail = model.maxResolutionDetail {
                    Text(detail)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 4) {
                ForEach(QualityProfile.allCases) { profile in
                    let available = model.isQualityAvailable(profile)
                    SegmentedChoiceButton(
                        title: profile.title,
                        systemImage: profile.systemImage,
                        isSelected: model.selectedQuality == profile,
                        isAvailable: available,
                        unavailableHelp: "\(profile.title) bu videoda yok."
                    ) {
                        model.updateSelectedQuality(profile)
                    }
                }
            }

            if model.selectedQuality.isVideoQuality {
                HStack(spacing: 4) {
                    ForEach(DownloadContainer.allCases) { container in
                        let available = model.isContainerAvailable(container, for: model.selectedQuality)
                        SegmentedChoiceButton(
                            title: container.title,
                            systemImage: container.systemImage,
                            isSelected: model.selectedContainer == container,
                            isAvailable: available,
                            unavailableHelp: "\(model.selectedQuality.title) için \(container.title) yok."
                        ) {
                            model.updateSelectedContainer(container)
                        }
                    }
                }
            }

            if model.isAnalyzingFormats == false {
                Text(model.formatSelectionDetail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct SegmentedChoiceButton: View {
    let title: String
    let systemImage: String
    let isSelected: Bool
    let isAvailable: Bool
    let unavailableHelp: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: systemImage)
                    .font(.caption)
                Text(title)
                    .strikethrough(isAvailable == false)
                    .lineLimit(1)
            }
            .font(.callout.weight(.semibold))
            .foregroundStyle(foregroundStyle)
            .frame(minWidth: 72, minHeight: 32)
            .padding(.horizontal, 8)
            .background(backgroundShape)
            .overlay(borderShape)
            .opacity(isAvailable ? 1 : 0.42)
        }
        .buttonStyle(.plain)
        .disabled(isAvailable == false)
        .help(isAvailable ? title : unavailableHelp)
    }

    private var foregroundStyle: Color {
        if isAvailable == false {
            return .secondary
        }
        if isSelected {
            return .white
        }
        return .primary
    }

    private var backgroundShape: some View {
        RoundedRectangle(cornerRadius: 7)
            .fill(isSelected && isAvailable ? Color.accentColor : Color.secondary.opacity(0.12))
    }

    private var borderShape: some View {
        RoundedRectangle(cornerRadius: 7)
            .stroke(isAvailable ? Color.clear : Color.secondary.opacity(0.35), lineWidth: 1)
    }
}
