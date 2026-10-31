import SwiftUI
import YouTubeJackCore

struct ContentView: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject private var updater = UpdateChecker.shared
    @AppStorage(AppPreferenceKeys.autoDetectClipboard) private var autoDetectClipboard = true
    @State private var mainContentLayout = MainContentLayout()
    private let surfaceColor = Color(nsColor: .windowBackgroundColor)

    private var isPlaylistPresented: Bool {
        model.media?.kind == .playlist
    }

    var body: some View {
        ZStack(alignment: .trailing) {
            appContent
                .disabled(model.isAnyDrawerPresented)
                .accessibilityElement(children: .contain)
                .accessibilityHidden(model.isAnyDrawerPresented)

            SettingsDrawerOverlay(isPresented: $model.isSettingsPanelPresented)
                .environmentObject(model)
                .allowsHitTesting(model.isSettingsPanelPresented)
                .zIndex(1)

            UpdateDrawerOverlay(isPresented: $model.isUpdatePanelPresented)
                .environmentObject(model)
                .allowsHitTesting(model.isUpdatePanelPresented)
                .zIndex(1)
        }
        .frame(minWidth: 1160, minHeight: 680)
        .background {
            ContentWindowSizing(layout: mainContentLayout)
                .allowsHitTesting(false)
        }
        .onPreferenceChange(MainContentLayoutKey.self) {
            mainContentLayout = $0
        }
        .toolbar {
            updateToolbarItem

            ToolbarItemGroup(placement: .automatic) {
                Button {
                    model.toggleUpdatePanel()
                } label: {
                    Label("Bilgi ve güncellemeler", systemImage: "info")
                }
                .help(model.isUpdatePanelPresented ? "Güncellemeleri kapat" : "Bilgi ve güncellemeleri aç")

                Button {
                    model.toggleSettingsPanel()
                } label: {
                    Label("Ayarlar", systemImage: "gearshape")
                }
                .help(model.isSettingsPanelPresented ? "Ayarları kapat" : "Ayarları aç")
            }
        }
        .animation(.smooth(duration: 0.32), value: model.isSettingsPanelPresented)
        .animation(.smooth(duration: 0.32), value: model.isUpdatePanelPresented)
        .onAppear {
            _ = try? UpdateLaunchConfirmation.writeIfRequested(arguments: ProcessInfo.processInfo.arguments)
            model.refreshDependencies()
            if autoDetectClipboard {
                model.detectClipboardURL()
            }
        }
    }

    @ToolbarContentBuilder
    private var updateToolbarItem: some ToolbarContent {
        if updater.shouldShowToolbarUpdate {
            if #available(macOS 26.0, *) {
                ToolbarItem(placement: .automatic) {
                    ToolbarUpdateButton()
                }
                .sharedBackgroundVisibility(.hidden)
            } else {
                ToolbarItem(placement: .automatic) {
                    ToolbarUpdateButton()
                }
            }
        }
    }

    private var appContent: some View {
        VStack(spacing: 0) {
            URLInputBar()
                .padding(.horizontal, 18)
                .padding(.top, 16)
                .padding(.bottom, 12)

            Divider()

            columns
        }
        .background(surfaceColor)
    }

    @ViewBuilder
    private var columns: some View {
        if isPlaylistPresented {
            HSplitView {
                mainColumn
                    .frame(minWidth: 480, idealWidth: 640)

                PlaylistEntriesView()
                    .frame(minWidth: 340, idealWidth: 400, maxWidth: .infinity)

                queueColumn
                    .frame(minWidth: 320, idealWidth: 440, maxWidth: 560)
            }
        } else {
            HStack(spacing: 0) {
                mainColumn

                Divider()

                queueColumn
                    .frame(width: 440)
            }
        }
    }

    private var queueColumn: some View {
        QueueView()
            .padding(16)
            .frame(maxHeight: .infinity, alignment: .top)
            .background(surfaceColor.overlay(Color.black.opacity(0.12)))
    }

    private var mainColumn: some View {
        VStack(spacing: 0) {
            previewControls

            Divider()

            if #available(macOS 26.0, *) {
                mainScrollView
                    .scrollEdgeEffectStyle(.hard, for: .top)
            } else {
                mainScrollView
            }

            VStack(spacing: 0) {
                Divider()

                DestinationPickerView(style: .bar)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 6)
            }
            .background(surfaceColor)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var mainScrollView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let statusMessage = model.statusMessage {
                    StatusBanner(message: statusMessage)
                }

                if let media = model.media {
                    MediaPreviewView(media: media)
                    QualityPickerView()
                    AudioLanguagePickerView()
                    SubtitlePickerView()
                } else {
                    EmptyStateView()
                }
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .background {
                GeometryReader { geometry in
                    Color.clear.preference(
                        key: MainContentLayoutKey.self,
                        value: MainContentLayout(contentSize: geometry.size)
                    )
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            GeometryReader { geometry in
                Color.clear.preference(
                    key: MainContentLayoutKey.self,
                    value: MainContentLayout(viewportHeight: geometry.size.height)
                )
            }
        }
    }

    private var previewControls: some View {
        Group {
            if #available(macOS 26.0, *) {
                GlassEffectContainer(spacing: 12) {
                    previewControlsContent
                }
            } else {
                previewControlsContent
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(.bar)
    }

    private var previewControlsContent: some View {
        HStack(spacing: 12) {
            DependencyCompactView(status: model.dependencyStatus)

            Spacer(minLength: 0)

            if model.isAnalyzing {
                AnalysisStatusPill(title: "Önizleme alınıyor")
            } else if model.isAnalyzingFormats {
                AnalysisStatusPill(
                    title: model.formatAnalysisTitle,
                    detail: model.formatAnalysisDetail,
                    progress: model.formatAnalysisProgress
                )
            }

            if isPlaylistPresented == false {
                AddToQueueButton()
                    .frame(width: 184)
            }
        }
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

private struct AnalysisStatusPill: View {
    let title: String
    var detail: String? = nil
    var progress: Double? = nil

    @ViewBuilder
    var body: some View {
        if #available(macOS 26.0, *) {
            statusContent
                .glassEffect(.regular, in: Capsule())
        } else {
            statusContent
                .background(.regularMaterial, in: Capsule())
        }
    }

    private var statusContent: some View {
        HStack(spacing: 8) {
            ProgressView(value: progress)
                .progressViewStyle(.circular)
                .controlSize(.small)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.callout.weight(.semibold))

                if let detail {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .monospacedDigit()
            .lineLimit(1)
        }
        .padding(.horizontal, 14)
        .frame(height: AppControlMetrics.height)
        .accessibilityElement(children: .combine)
        .help([title, detail].compactMap { $0 }.joined(separator: "\n"))
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
