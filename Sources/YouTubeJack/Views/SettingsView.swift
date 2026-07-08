import SwiftUI
import YouTubeJackCore

struct SettingsDrawerOverlay: View {
    @Binding var isPresented: Bool

    var body: some View {
        ZStack(alignment: .leading) {
            Color.black.opacity(isPresented ? 0.22 : 0)
                .onTapGesture {
                    isPresented = false
                }

            SettingsDrawer(isPresented: $isPresented)
                .padding(.leading, 16)
                .padding(.vertical, 16)
                .offset(x: isPresented ? 0 : -480)
                .opacity(isPresented ? 1 : 0.96)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

struct SettingsView: View {
    @State private var selectedSection: SettingsPanelSection = .general

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Ayarlar")
                .font(.title2.weight(.semibold))

            SettingsPanelContent(selectedSection: $selectedSection)
        }
        .padding(20)
        .frame(width: 620, height: 420, alignment: .topLeading)
    }
}

private enum SettingsPanelSection: String, CaseIterable, Identifiable {
    case general
    case tools

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general:
            return "Genel"
        case .tools:
            return "Araçlar"
        }
    }

    var systemImage: String {
        switch self {
        case .general:
            return "gearshape"
        case .tools:
            return "wrench.and.screwdriver"
        }
    }
}

private struct SettingsDrawer: View {
    @Binding var isPresented: Bool
    @State private var selectedSection: SettingsPanelSection = .general

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Button {
                    isPresented = false
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .bold))
                        .frame(width: 30, height: 30)
                }
                .buttonStyle(.plain)
                .background(.thinMaterial, in: Circle())
                .help("Ayarları kapat")

                Text("Ayarlar")
                    .font(.title2.weight(.semibold))

                Spacer()
            }

            SettingsPanelContent(selectedSection: $selectedSection)
        }
        .padding(20)
        .frame(width: 430)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(Color.primary.opacity(0.14), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.28), radius: 28, x: 10, y: 0)
    }
}

private struct SettingsPanelContent: View {
    @Binding var selectedSection: SettingsPanelSection

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                ForEach(SettingsPanelSection.allCases) { section in
                    SettingsPanelTab(
                        section: section,
                        isSelected: selectedSection == section
                    ) {
                        selectedSection = section
                    }
                }
            }

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    switch selectedSection {
                    case .general:
                        GeneralSettingsPane()
                    case .tools:
                        ToolsSettingsPane()
                    }
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .padding(.bottom, 8)
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .scrollIndicators(.visible)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}

private struct SettingsPanelTab: View {
    let section: SettingsPanelSection
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(section.title, systemImage: section.systemImage)
                .font(.callout.weight(.semibold))
                .lineLimit(1)
                .frame(maxWidth: .infinity)
                .frame(height: 42)
                .foregroundStyle(isSelected ? Color.white : Color.primary)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(isSelected ? Color.orange.opacity(0.95) : Color.secondary.opacity(0.12))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(isSelected ? Color.orange.opacity(0.45) : Color.primary.opacity(0.08), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }
}

private struct GeneralSettingsPane: View {
    @EnvironmentObject private var model: AppModel
    @AppStorage(AppPreferenceKeys.autoDetectClipboard) private var autoDetectClipboard = true
    @AppStorage(AppPreferenceKeys.defaultQuality) private var defaultQuality = AppPreferenceDefaults.defaultQuality
    @AppStorage(AppPreferenceKeys.defaultContainer) private var defaultContainer = AppPreferenceDefaults.defaultContainer

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SettingsGroup(title: "Varsayılanlar", systemImage: "slider.horizontal.3") {
                SettingsRow(title: "Çözünürlük") {
                    Picker("Varsayılan çözünürlük", selection: $defaultQuality) {
                        ForEach(QualityProfile.allCases) { profile in
                            Text(profile.title).tag(profile.rawValue)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 170)
                    .onChange(of: defaultQuality) { _, newValue in
                        model.updateSelectedQuality(QualityProfile(rawValue: newValue) ?? .q1080)
                    }
                }

                SettingsRow(title: "Format") {
                    Picker("Varsayılan format", selection: $defaultContainer) {
                        ForEach(DownloadContainer.allCases) { container in
                            Text(container.title).tag(container.rawValue)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 170)
                    .onChange(of: defaultContainer) { _, newValue in
                        model.updateSelectedContainer(DownloadContainer(rawValue: newValue) ?? .mp4)
                    }
                }
            }

            Divider()

            SettingsGroup(title: "Davranış", systemImage: "sparkles") {
                SettingsRow(title: "Açılışta panoyu kontrol et") {
                    Toggle("Açılışta panoyu kontrol et", isOn: $autoDetectClipboard)
                        .labelsHidden()
                        .toggleStyle(.switch)
                }
            }

            Divider()

            SettingsGroup(title: "İndirme klasörü", systemImage: "folder") {
                DestinationPickerView()
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}

private struct ToolsSettingsPane: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject private var updater = UpdateChecker.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SettingsGroup(title: "Araç durumu", systemImage: "checkmark.seal") {
                DependencyRow(name: "yt-dlp", tool: model.dependencyStatus.ytdlp, required: true)
                DependencyRow(name: "ffmpeg", tool: model.dependencyStatus.ffmpeg, required: false)
                DependencyPathRow(name: "Node/Deno", path: model.dependencyStatus.jsRuntimePath, required: false)
            }

            Divider()

            SettingsGroup(title: "YouTubeJack", systemImage: "app.badge") {
                AppUpdateSection()
            }

            Divider()

            SettingsGroup(title: "yt-dlp", systemImage: "square.and.arrow.down") {
                YTDLPUpdateSection()
            }

            Button {
                model.refreshDependencies()
            } label: {
                Label("Araçları yenile", systemImage: "arrow.clockwise")
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .onAppear {
            Task {
                await updater.checkForUpdates(force: true)
                await model.checkYTDLPUpdate()
            }
        }
    }
}

private struct SettingsGroup<Content: View>: View {
    let title: String
    let systemImage: String
    let content: Content

    init(title: String, systemImage: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.systemImage = systemImage
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: systemImage)
                .font(.headline)
                .foregroundStyle(.secondary)

            content
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct SettingsRow<Content: View>: View {
    let title: String
    let content: Content

    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        HStack(spacing: 12) {
            Text(title)
                .font(.callout.weight(.semibold))
                .lineLimit(1)

            Spacer()

            content
                .frame(minWidth: 190, alignment: .trailing)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct YTDLPUpdateSection: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(updateDetail)
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
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

                if model.isUpdatingYTDLP {
                    ProgressView()
                        .controlSize(.small)
                }
            }

            if let message = model.ytdlpUpdateMessage {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
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
        VStack(alignment: .leading, spacing: 10) {
            Text("Kurulu: \(updater.currentVersion)")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack {
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

                if updater.isChecking {
                    ProgressView()
                        .controlSize(.small)
                }
            }

            updateStatus
        }
    }

    @ViewBuilder
    private var updateStatus: some View {
        if updater.isDownloading {
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
