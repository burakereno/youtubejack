import SwiftUI
import YouTubeJackCore

struct SettingsView: View {
    @EnvironmentObject private var model: AppModel
    @AppStorage(AppPreferenceKeys.autoDetectClipboard) private var autoDetectClipboard = true
    @AppStorage(AppPreferenceKeys.defaultQuality) private var defaultQuality = AppPreferenceDefaults.defaultQuality
    @AppStorage(AppPreferenceKeys.defaultContainer) private var defaultContainer = AppPreferenceDefaults.defaultContainer

    var body: some View {
        TabView {
            Form {
                Picker("Varsayılan çözünürlük", selection: $defaultQuality) {
                    ForEach(QualityProfile.allCases) { profile in
                        Text(profile.title).tag(profile.rawValue)
                    }
                }
                .onChange(of: defaultQuality) { _, newValue in
                    model.updateSelectedQuality(QualityProfile(rawValue: newValue) ?? .q1080)
                }

                Picker("Varsayılan format", selection: $defaultContainer) {
                    ForEach(DownloadContainer.allCases) { container in
                        Text(container.title).tag(container.rawValue)
                    }
                }
                .onChange(of: defaultContainer) { _, newValue in
                    model.updateSelectedContainer(DownloadContainer(rawValue: newValue) ?? .mp4)
                }

                Toggle("Açılışta panoyu kontrol et", isOn: $autoDetectClipboard)

                DestinationPickerView()
            }
            .padding(20)
            .tabItem {
                Label("Genel", systemImage: "gearshape")
            }

            DependencyStatusView()
                .padding(20)
                .tabItem {
                    Label("Araçlar", systemImage: "wrench.and.screwdriver")
                }
        }
        .frame(width: 620, height: 420)
    }
}

private struct DependencyStatusView: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject private var updater = UpdateChecker.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            DependencyRow(name: "yt-dlp", tool: model.dependencyStatus.ytdlp, required: true)
            DependencyRow(name: "ffmpeg", tool: model.dependencyStatus.ffmpeg, required: false)
            DependencyPathRow(name: "Node/Deno", path: model.dependencyStatus.jsRuntimePath, required: false)

            Divider()

            AppUpdateSection()

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("yt-dlp güncelleme")
                            .font(.headline)
                        Text(updateDetail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    if model.isUpdatingYTDLP {
                        ProgressView()
                            .controlSize(.small)
                    }

                    Button {
                        Task { await model.checkYTDLPUpdate() }
                    } label: {
                        Label("Kontrol Et", systemImage: "arrow.clockwise")
                    }
                    .disabled(model.isUpdatingYTDLP)

                    Button {
                        Task { await model.updateYTDLP() }
                    } label: {
                        Label("Güncelle", systemImage: "square.and.arrow.down")
                    }
                    .disabled(model.isUpdatingYTDLP)
                }

                if let message = model.ytdlpUpdateMessage {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Button {
                model.refreshDependencies()
            } label: {
                Label("Yenile", systemImage: "arrow.clockwise")
            }
        }
        .onAppear {
            Task {
                await updater.checkForUpdates(force: true)
                await model.checkYTDLPUpdate()
            }
        }
    }

    private var updateDetail: String {
        let installed = model.ytdlpInstalledVersion ?? "yok"
        let latest = model.ytdlpLatestVersion ?? "bilinmiyor"
        return "Kurulu: \(installed) · Son sürüm: \(latest)"
    }
}

private struct AppUpdateSection: View {
    @ObservedObject private var updater = UpdateChecker.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("YouTubeJack güncelleme")
                        .font(.headline)
                    Text("Kurulu: \(updater.currentVersion)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if updater.updateAvailable, let latest = updater.latestVersion {
                    UpdateButton(version: latest)
                } else {
                    Button {
                        Task { await updater.checkForUpdates(force: true) }
                    } label: {
                        if updater.isChecking {
                            Label("Kontrol", systemImage: "arrow.triangle.2.circlepath")
                        } else {
                            Label("Kontrol Et", systemImage: "arrow.clockwise")
                        }
                    }
                    .disabled(updater.isChecking)
                }
            }

            updateStatus
        }
    }

    @ViewBuilder
    private var updateStatus: some View {
        if updater.isChecking {
            Text("Uygulama güncellemesi kontrol ediliyor...")
                .font(.caption)
                .foregroundStyle(.secondary)
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
                .lineLimit(2)
        } else if updater.isUpToDate && updater.lastCheckCompletedAt != nil {
            Text("YouTubeJack güncel.")
                .font(.caption)
                .foregroundStyle(.green)
        } else if updater.updatesEnabled == false {
            Text("Otomatik kurulum yayın build'lerinde aktif olur.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

private struct DependencyRow: View {
    let name: String
    let tool: RuntimeTool?
    let required: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: tool == nil ? "xmark.octagon" : "checkmark.circle")
                .foregroundStyle(tool == nil ? (required ? .red : .orange) : .green)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text(name)
                        .font(.headline)
                    if let origin = tool?.origin {
                        Text(origin.title)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                }
                Text(tool?.path ?? (required ? "Gerekli" : "Önerilir"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
        }
    }
}

private struct DependencyPathRow: View {
    let name: String
    let path: String?
    let required: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: path == nil ? "xmark.octagon" : "checkmark.circle")
                .foregroundStyle(path == nil ? (required ? .red : .orange) : .green)
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.headline)
                Text(path ?? (required ? "Gerekli" : "Önerilir"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
        }
    }
}
