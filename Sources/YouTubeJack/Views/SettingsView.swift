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
    private let contentWidth: CGFloat = 580

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Ayarlar")
                .font(.title2.weight(.semibold))

            SettingsPanelContent(selectedSection: $selectedSection, contentWidth: contentWidth)
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
    private let contentWidth: CGFloat = 390

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

            SettingsPanelContent(selectedSection: $selectedSection, contentWidth: contentWidth)
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
    let contentWidth: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Picker("Ayar bölümü", selection: $selectedSection) {
                ForEach(SettingsPanelSection.allCases) { section in
                    Label(section.title, systemImage: section.systemImage)
                        .tag(section)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .controlSize(.large)
            .tint(.orange)
            .frame(width: contentWidth)

            SettingsDivider(width: contentWidth)

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    switch selectedSection {
                    case .general:
                        GeneralSettingsPane(contentWidth: contentWidth)
                    case .tools:
                        ToolsSettingsPane(contentWidth: contentWidth)
                    }
                }
                .frame(width: contentWidth, alignment: .topLeading)
                .padding(.bottom, 8)
            }
            .frame(width: contentWidth, alignment: .topLeading)
            .scrollIndicators(.visible)
        }
        .frame(width: contentWidth, alignment: .topLeading)
    }
}

private struct GeneralSettingsPane: View {
    @EnvironmentObject private var model: AppModel
    @AppStorage(AppPreferenceKeys.autoDetectClipboard) private var autoDetectClipboard = true
    @AppStorage(AppPreferenceKeys.defaultQuality) private var defaultQuality = AppPreferenceDefaults.defaultQuality
    @AppStorage(AppPreferenceKeys.defaultContainer) private var defaultContainer = AppPreferenceDefaults.defaultContainer
    let contentWidth: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SettingsGroup(title: "Varsayılanlar", systemImage: "slider.horizontal.3", contentWidth: contentWidth) {
                SettingsRow(title: "Çözünürlük", contentWidth: contentWidth) {
                    DefaultQualityMenu(selection: $defaultQuality) { newValue in
                        model.updateSelectedQuality(QualityProfile(rawValue: newValue) ?? .q1080)
                    }
                }

                SettingsRow(title: "Format", contentWidth: contentWidth) {
                    DefaultContainerSegmentedControl(selection: $defaultContainer) { newValue in
                        model.updateSelectedContainer(DownloadContainer(rawValue: newValue) ?? .mp4)
                    }
                }
            }

            SettingsDivider(width: contentWidth)

            SettingsGroup(title: "Davranış", systemImage: "sparkles", contentWidth: contentWidth) {
                SettingsRow(title: "Açılışta panoyu kontrol et", contentWidth: contentWidth) {
                    Toggle("Açılışta panoyu kontrol et", isOn: $autoDetectClipboard)
                        .labelsHidden()
                        .toggleStyle(.switch)
                }
            }

            SettingsDivider(width: contentWidth)

            SettingsGroup(title: "İndirme klasörü", systemImage: "folder", contentWidth: contentWidth) {
                DestinationPickerView()
                    .frame(width: contentWidth, alignment: .leading)
            }
        }
        .frame(width: contentWidth, alignment: .topLeading)
    }
}

private struct SettingsDivider: View {
    let width: CGFloat

    var body: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.14))
            .frame(width: width, height: 1)
    }
}

private struct ToolsSettingsPane: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject private var updater = UpdateChecker.shared
    let contentWidth: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SettingsGroup(title: "Araç durumu", systemImage: "checkmark.seal", contentWidth: contentWidth) {
                DependencyRow(name: "yt-dlp", tool: model.dependencyStatus.ytdlp, required: true)
                DependencyRow(name: "ffmpeg", tool: model.dependencyStatus.ffmpeg, required: false)
                DependencyPathRow(name: "Node/Deno", path: model.dependencyStatus.jsRuntimePath, required: false)
            }

            SettingsDivider(width: contentWidth)

            SettingsGroup(title: "YouTubeJack", systemImage: "app.badge", contentWidth: contentWidth) {
                AppUpdateSection()
            }

            SettingsDivider(width: contentWidth)

            SettingsGroup(title: "yt-dlp", systemImage: "square.and.arrow.down", contentWidth: contentWidth) {
                YTDLPUpdateSection()
            }

            Button {
                model.refreshDependencies()
            } label: {
                Label("Araçları yenile", systemImage: "arrow.clockwise")
            }
        }
        .frame(width: contentWidth, alignment: .topLeading)
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
    let contentWidth: CGFloat
    let content: Content

    init(title: String, systemImage: String, contentWidth: CGFloat, @ViewBuilder content: () -> Content) {
        self.title = title
        self.systemImage = systemImage
        self.contentWidth = contentWidth
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: systemImage)
                .font(.headline)
                .foregroundStyle(.secondary)

            content
                .frame(width: contentWidth, alignment: .leading)
        }
        .frame(width: contentWidth, alignment: .leading)
    }
}

private struct SettingsRow<Content: View>: View {
    let title: String
    let contentWidth: CGFloat
    let content: Content
    private let controlWidth: CGFloat = 190
    private let columnSpacing: CGFloat = 12

    init(title: String, contentWidth: CGFloat, @ViewBuilder content: () -> Content) {
        self.title = title
        self.contentWidth = contentWidth
        self.content = content()
    }

    var body: some View {
        HStack(spacing: columnSpacing) {
            Text(title)
                .font(.callout.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .frame(width: contentWidth - controlWidth - columnSpacing, alignment: .leading)

            HStack(spacing: 0) {
                Spacer(minLength: 0)
                content
                    .fixedSize(horizontal: true, vertical: false)
            }
            .frame(width: controlWidth, alignment: .trailing)
        }
        .frame(width: contentWidth, alignment: .leading)
    }
}

private struct DefaultQualityMenu: View {
    @Binding var selection: String
    let onChange: (String) -> Void
    @State private var isShowingOptions = false

    var body: some View {
        Button {
            isShowingOptions.toggle()
        } label: {
            HStack(spacing: 10) {
                Text(selectedTitle)
                    .font(.callout.weight(.semibold))
                    .lineLimit(1)

                Spacer(minLength: 0)

                Image(systemName: "chevron.up.chevron.down")
                    .font(.callout.weight(.bold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 14)
            .frame(width: 170, height: 36)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.black.opacity(0.42))
            )
            .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .fixedSize()
        .popover(isPresented: $isShowingOptions, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(QualityProfile.allCases) { profile in
                    Button {
                        selection = profile.rawValue
                        onChange(profile.rawValue)
                        isShowingOptions = false
                    } label: {
                        HStack(spacing: 8) {
                            Text(profile.title)
                                .lineLimit(1)
                            Spacer()
                            if profile.rawValue == selection {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.orange)
                            }
                        }
                        .padding(.horizontal, 10)
                        .frame(width: 170, height: 30)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(8)
        }
    }

    private var selectedTitle: String {
        QualityProfile(rawValue: selection)?.title ?? QualityProfile.best.title
    }
}

private struct DefaultContainerSegmentedControl: View {
    @Binding var selection: String
    let onChange: (String) -> Void

    var body: some View {
        HStack(spacing: 0) {
            ForEach(DownloadContainer.allCases) { container in
                Button {
                    selection = container.rawValue
                    onChange(container.rawValue)
                } label: {
                    Text(container.title)
                        .font(.callout.weight(.semibold))
                        .lineLimit(1)
                        .frame(maxWidth: .infinity)
                        .frame(height: 34)
                        .foregroundStyle(isSelected(container) ? .white : .primary)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(isSelected(container) ? Color.orange : Color.clear)
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .frame(width: 170, height: 34)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.black.opacity(0.42))
        )
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .fixedSize()
    }

    private func isSelected(_ container: DownloadContainer) -> Bool {
        selection == container.rawValue
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
