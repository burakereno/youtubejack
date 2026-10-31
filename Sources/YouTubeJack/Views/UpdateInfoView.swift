import SwiftUI
import YouTubeJackCore

struct UpdateDrawerOverlay: View {
    @Binding var isPresented: Bool

    var body: some View {
        SideDrawerOverlay(
            title: "Bilgi ve güncellemeler",
            closeLabel: "Güncellemeleri kapat",
            isPresented: $isPresented
        ) {
            UpdateInfoView(isPresented: isPresented)
        }
    }
}

struct UpdateInfoView: View {
    @EnvironmentObject private var model: AppModel
    let isPresented: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                UpdatePanelSection("YouTubeJack", systemImage: "app.badge") {
                    AppUpdateSection()
                }

                UpdatePanelSection("yt-dlp", systemImage: "square.and.arrow.down") {
                    YTDLPUpdateSection()
                }

                UpdatePanelSection("Araç durumu", systemImage: "checkmark.seal") {
                    VStack(alignment: .leading, spacing: 14) {
                        DependencyRow(name: "yt-dlp", tool: model.dependencyStatus.ytdlp, required: true)

                        Divider().padding(.leading, 28)

                        DependencyRow(name: "ffmpeg", tool: model.dependencyStatus.ffmpeg, required: false)

                        Divider().padding(.leading, 28)

                        DependencyPathRow(name: "Node/Deno", path: model.dependencyStatus.jsRuntimePath, required: false)

                        Button {
                            model.refreshDependencies()
                        } label: {
                            Label("Araçları yenile", systemImage: "arrow.clockwise")
                                .frame(maxWidth: .infinity)
                        }
                        .modifier(UpdatePanelSecondaryButtonStyle())
                    }
                }
            }
            .padding(.top, 4)
            .padding(.bottom, 12)
        }
        .frame(width: 390, alignment: .topLeading)
        .task(id: isPresented) {
            guard isPresented else { return }
            model.refreshDependencies()
            await UpdateChecker.shared.checkForUpdates(force: true)
            await model.checkYTDLPUpdate()
        }
    }
}

private struct UpdatePanelSection<Content: View>: View {
    let title: String
    let systemImage: String
    @ViewBuilder let content: Content

    init(_ title: String, systemImage: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.systemImage = systemImage
        self.content = content()
    }

    var body: some View {
        GroupBox {
            content
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
        } label: {
            Label(title, systemImage: systemImage)
                .font(.callout.weight(.semibold))
                .foregroundStyle(.secondary)
        }
    }
}

private struct UpdatePanelSecondaryButtonStyle: ViewModifier {
    func body(content: Content) -> some View {
        Group {
            if #available(macOS 26.0, *) {
                content.buttonStyle(.glass)
            } else {
                content.buttonStyle(.bordered)
            }
        }
        .buttonBorderShape(.capsule)
        .controlSize(.large)
        .modifier(FlexibleControlSizing())
        .frame(height: AppControlMetrics.height)
    }
}

private struct UpdateVersionRow: View {
    let title: String
    let value: String

    var body: some View {
        LabeledContent {
            Text(value)
                .monospacedDigit()
                .frame(maxWidth: .infinity, alignment: .trailing)
        } label: {
            Text(title)
                .foregroundStyle(.secondary)
        }
        .font(.callout)
    }
}

private struct UpdateActivityStatus: View {
    let message: String
    var isBusy = false

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            if isBusy {
                ProgressView()
                    .controlSize(.small)
                    .frame(width: 14, height: 14)
                    .accessibilityHidden(true)
            }

            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct YTDLPUpdateSection: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(spacing: 6) {
                UpdateVersionRow(title: "Kurulu", value: model.ytdlpInstalledVersion ?? "Yüklü değil")
                UpdateVersionRow(title: "Son sürüm", value: model.ytdlpLatestVersion ?? "Bilinmiyor")
            }

            HStack(spacing: 10) {
                Button {
                    Task { await model.checkYTDLPUpdate() }
                } label: {
                    Label("Kontrol et", systemImage: "arrow.clockwise")
                        .lineLimit(1)
                        .frame(maxWidth: .infinity)
                }
                .modifier(UpdatePanelSecondaryButtonStyle())
                .disabled(model.isUpdatingYTDLP)

                Button {
                    Task { await model.updateYTDLP() }
                } label: {
                    Label("Güncelle", systemImage: "square.and.arrow.down")
                        .lineLimit(1)
                        .frame(maxWidth: .infinity)
                }
                .modifier(NativeProminentButton())
                .buttonBorderShape(.capsule)
                .controlSize(.large)
                .modifier(FlexibleControlSizing())
                .frame(height: AppControlMetrics.height)
                .disabled(model.isUpdatingYTDLP)
            }

            if let message = model.ytdlpUpdateMessage {
                UpdateActivityStatus(message: message, isBusy: model.isUpdatingYTDLP)
            }
        }
    }
}

private struct AppUpdateSection: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject private var updater = UpdateChecker.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            UpdateVersionRow(title: "Kurulu", value: updater.currentVersion)

            HStack(spacing: 10) {
                Button {
                    Task { await updater.checkForUpdates(force: true) }
                } label: {
                    Label("Kontrol et", systemImage: "arrow.clockwise")
                        .lineLimit(1)
                        .frame(maxWidth: .infinity)
                }
                .modifier(UpdatePanelSecondaryButtonStyle())
                .disabled(updater.isChecking || updater.isDownloading || updater.isInstalling)

                if updater.updateAvailable, let latest = updater.latestVersion {
                    UpdateButton(version: latest)
                }
            }

            updateStatus
            if updater.updateAvailable, model.canInstallAppUpdate == false, updater.isDownloading == false, updater.isInstalling == false {
                UpdateActivityStatus(message: UpdateChecker.unfinishedQueueMessage)
            }
        }
    }

    @ViewBuilder
    private var updateStatus: some View {
        if updater.isInstalling {
            UpdateActivityStatus(message: "Güncelleme kuruluyor; uygulama yeniden açılacak…", isBusy: true)
        } else if updater.isChecking {
            UpdateActivityStatus(message: "Güncellemeler kontrol ediliyor…", isBusy: true)
        } else if updater.isDownloading {
            ProgressView(value: updater.downloadProgress)
        } else if updater.updateAvailable, let latest = updater.latestVersion {
            Text("Yeni sürüm hazır: \(latest)")
                .font(.caption)
                .foregroundStyle(.orange)
        } else if let error = updater.lastError {
            Text("Güncelleme kontrolü başarısız: \(error)")
                .font(.caption)
                .foregroundStyle(.red)
                .lineLimit(3)
        } else if updater.isUpToDate && updater.lastCheckCompletedAt != nil {
            Text("YouTubeJack güncel.")
                .font(.caption)
                .foregroundStyle(.green)
        } else if updater.updatesEnabled == false {
            Text("Bu sürümde otomatik kurulum kullanılamıyor.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct DependencyRow: View {
    let name: String
    let tool: RuntimeTool?
    let required: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: tool == nil ? "xmark.octagon" : "checkmark.circle")
                .font(.body)
                .foregroundStyle(tool == nil ? (required ? .red : .orange) : .green)
                .frame(width: 18)
                .accessibilityLabel(tool == nil ? (required ? "Eksik" : "Önerilir") : "Hazır")
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(name)
                        .font(.callout.weight(.semibold))
                    if let origin = tool?.origin {
                        Text(origin.title)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Text(tool?.path ?? (required ? "Gerekli" : "Önerilir"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(tool?.path ?? (required ? "Gerekli" : "Önerilir"))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct DependencyPathRow: View {
    let name: String
    let path: String?
    let required: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: path == nil ? "xmark.octagon" : "checkmark.circle")
                .font(.body)
                .foregroundStyle(path == nil ? (required ? .red : .orange) : .green)
                .frame(width: 18)
                .accessibilityLabel(path == nil ? (required ? "Eksik" : "Önerilir") : "Hazır")
            VStack(alignment: .leading, spacing: 4) {
                Text(name)
                    .font(.callout.weight(.semibold))
                Text(path ?? (required ? "Gerekli" : "Önerilir"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(path ?? (required ? "Gerekli" : "Önerilir"))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
