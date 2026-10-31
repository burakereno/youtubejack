import SwiftUI
import YouTubeJackCore

struct SettingsDrawerOverlay: View {
    @Binding var isPresented: Bool

    var body: some View {
        SideDrawerOverlay(title: "Ayarlar", closeLabel: "Ayarları kapat", isPresented: $isPresented) {
            SettingsPanelContent(contentWidth: 390)
        }
    }
}

struct SettingsView: View {
    private let contentWidth: CGFloat = 580

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Ayarlar")
                .font(.title2.weight(.semibold))

            SettingsPanelContent(contentWidth: contentWidth)
        }
        .padding(20)
        .frame(width: 620, height: 420, alignment: .topLeading)
    }
}

private struct SettingsPanelContent: View {
    let contentWidth: CGFloat

    var body: some View {
        ScrollView {
            GeneralSettingsPane(contentWidth: contentWidth)
                .padding(.bottom, 8)
        }
        .frame(width: contentWidth, alignment: .topLeading)
        .scrollIndicators(.visible)
    }
}

private struct GeneralSettingsPane: View {
    @EnvironmentObject private var model: AppModel
    @AppStorage(AppPreferenceKeys.autoDetectClipboard) private var autoDetectClipboard = true
    @AppStorage(AppPreferenceKeys.defaultQuality) private var defaultQuality = AppPreferenceDefaults.defaultQuality
    @AppStorage(AppPreferenceKeys.defaultContainer) private var defaultContainer = AppPreferenceDefaults.defaultContainer
    @AppStorage(AppPreferenceKeys.defaultVideoCodec) private var defaultVideoCodec = AppPreferenceDefaults.defaultVideoCodec
    let contentWidth: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SettingsGroup(title: "Varsayılanlar", systemImage: "slider.horizontal.3", contentWidth: contentWidth) {
                SettingsRow(title: "Çözünürlük", contentWidth: contentWidth) {
                    DefaultQualityMenu(selection: $defaultQuality) { newValue in
                        model.updateDefaultQuality(QualityProfile(rawValue: newValue) ?? .q1080)
                    }
                }

                SettingsRow(title: "Format", contentWidth: contentWidth) {
                    DefaultContainerSegmentedControl(selection: $defaultContainer) { newValue in
                        model.updateDefaultContainer(DownloadContainer(rawValue: newValue) ?? .mp4)
                    }
                }

                SettingsRow(title: "Video codec’i", contentWidth: contentWidth) {
                    MenuField("Video codec’i", value: (VideoCodecPreference(rawValue: defaultVideoCodec) ?? .automatic).title) {
                        ForEach(VideoCodecPreference.allCases) { codec in
                            MenuChoice(title: codec.title, isSelected: defaultVideoCodec == codec.rawValue) {
                                defaultVideoCodec = codec.rawValue
                                model.updateDefaultVideoCodec(codec)
                            }
                        }
                    }
                    .frame(width: 170)
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

    var body: some View {
        MenuField("Varsayılan çözünürlük", value: selectedTitle) {
            ForEach(QualityProfile.allCases) { profile in
                MenuChoice(title: profile.title, isSelected: selection == profile.rawValue) {
                    selection = profile.rawValue
                    onChange(profile.rawValue)
                }
            }
        }
        .frame(width: 170)
    }

    private var selectedTitle: String {
        QualityProfile(rawValue: selection)?.title ?? QualityProfile.best.title
    }
}

private struct DefaultContainerSegmentedControl: View {
    @Binding var selection: String
    let onChange: (String) -> Void

    var body: some View {
        Picker("Varsayılan dosya biçimi", selection: $selection) {
            ForEach(DownloadContainer.allCases) { container in
                Text(container.title).tag(container.rawValue)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .controlSize(.extraLarge)
        .modifier(FlexibleControlSizing())
        .frame(width: 170, height: AppControlMetrics.height)
        .onChange(of: selection) { _, newValue in
            onChange(newValue)
        }
    }
}
