import SwiftUI
import YouTubeJackCore

struct ContentView: View {
    @EnvironmentObject private var model: AppModel
    @AppStorage(AppPreferenceKeys.autoDetectClipboard) private var autoDetectClipboard = true

    var body: some View {
        VStack(spacing: 0) {
            URLInputBar()
                .padding(.horizontal, 18)
                .padding(.top, 16)
                .padding(.bottom, 12)

            Divider()

            HStack(spacing: 0) {
                mainColumn

                Divider()

                QueueView()
                    .padding(16)
                    .frame(width: 440)
                    .frame(maxHeight: .infinity, alignment: .top)
                    .background(.ultraThinMaterial)
            }
        }
        .frame(minWidth: 1160, minHeight: 680)
        .toolbar {
            ToolbarItem {
                Button {
                    model.toggleQueuePlayback()
                } label: {
                    Label(model.queueControlTitle, systemImage: model.queueControlIcon)
                }
                .disabled(model.canToggleQueue == false)
                .help(model.queueControlTitle)
            }
        }
        .onAppear {
            model.refreshDependencies()
            if autoDetectClipboard {
                model.detectClipboardURL()
            }
        }
    }

    private var mainColumn: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let statusMessage = model.statusMessage {
                    StatusBanner(message: statusMessage)
                }

                HStack(spacing: 12) {
                    DependencyCompactView(status: model.dependencyStatus)

                    Spacer()

                    if model.isAnalyzing {
                        AnalysisStatusPill(title: "Önizleme alınıyor")
                    } else if model.isAnalyzingFormats {
                        AnalysisStatusPill(title: "Formatlar analiz ediliyor")
                    }

                    AddToQueueButton()
                }

                if let media = model.media {
                    MediaPreviewView(media: media)
                    QualityPickerView()
                    DestinationPickerView()

                    if media.kind == .playlist {
                        PlaylistEntriesView()
                    }
                } else {
                    EmptyStateView()
                }
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct StatusBanner: View {
    let message: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle")
                .foregroundStyle(.orange)
            Text(message)
                .lineLimit(3)
            Spacer()
        }
        .padding(12)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct DependencyCompactView: View {
    let status: DependencyStatus

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: status.isReady ? "checkmark.circle" : "xmark.octagon")
                .foregroundStyle(status.isReady ? .green : .red)
            Text(status.summary)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }
}

private struct AddToQueueButton: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        Button {
            model.addSelectedToQueue()
        } label: {
            Label("Kuyruğa ekle", systemImage: "text.badge.plus")
                .font(.callout.weight(.semibold))
                .lineLimit(1)
                .padding(.horizontal, 18)
                .frame(minWidth: 184)
                .frame(height: 40)
                .foregroundStyle(model.canAddToQueue ? .white : .secondary)
                .background(background)
                .overlay(border)
        }
        .buttonStyle(.plain)
        .disabled(model.canAddToQueue == false)
        .help("Seçili kalite ve formatla kuyruğa ekle")
    }

    private var background: some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(model.canAddToQueue ? Color.green.opacity(0.92) : Color.secondary.opacity(0.12))
    }

    private var border: some View {
        RoundedRectangle(cornerRadius: 8)
            .stroke(model.canAddToQueue ? Color.green.opacity(0.55) : Color.secondary.opacity(0.24), lineWidth: 1)
    }
}

private struct AnalysisStatusPill: View {
    let title: String

    var body: some View {
        HStack(spacing: 8) {
            ProgressView()
                .controlSize(.small)
                .tint(.orange)

            Text(title)
                .font(.callout.weight(.semibold))
                .foregroundStyle(.orange)
                .lineLimit(1)
        }
        .padding(.horizontal, 13)
        .frame(height: 40)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.orange.opacity(0.16))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.orange.opacity(0.45), lineWidth: 1)
        )
        .help(title)
    }
}

private struct EmptyStateView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "link.badge.plus")
                .font(.system(size: 44))
                .foregroundStyle(.secondary)
            Text("YouTube linki bekleniyor")
                .font(.title3.weight(.semibold))
            Text("Video veya playlist linki yapıştır.")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 180)
    }
}
