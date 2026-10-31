import SwiftUI
import UniformTypeIdentifiers
import YouTubeJackCore

struct QueueView: View {
    @EnvironmentObject private var model: AppModel
    @State private var draggedItemID: UUID?
    @State private var dropTargetID: UUID?
    @State private var isDroppingAtEnd = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header

            if model.queue.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(model.queue) { item in
                            DownloadQueueRow(
                                item: item,
                                draggedItemID: $draggedItemID,
                                isDropTarget: dropTargetID == item.id
                            )
                            .opacity(draggedItemID == item.id ? 0.62 : 1)
                            .onDrop(of: [UTType.text], isTargeted: dropTargetBinding(for: item.id)) { _ in
                                guard let draggedItemID else { return false }
                                model.moveQueueItem(draggedID: draggedItemID, before: item.id)
                                self.draggedItemID = nil
                                self.dropTargetID = nil
                                return true
                            }
                        }

                        endDropTarget
                            .onDrop(of: [UTType.text], isTargeted: $isDroppingAtEnd) { _ in
                                guard let draggedItemID else { return false }
                                model.moveQueueItemToEnd(draggedItemID)
                                self.draggedItemID = nil
                                self.isDroppingAtEnd = false
                                return true
                            }
                    }
                }
                .scrollIndicators(.visible)
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private var header: some View {
        HStack(spacing: 10) {
            HStack(spacing: 8) {
                Text("Kuyruk")
                    .font(.headline)

                Text("\(model.queue.count)")
                    .font(.caption.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.secondary.opacity(0.10), in: Capsule())
                    .accessibilityLabel("\(model.queue.count) öğe")
            }
            .accessibilityElement(children: .combine)

            Spacer(minLength: 12)

            Button {
                model.toggleQueuePlayback()
            } label: {
                Label(model.queueControlTitle, systemImage: model.queueControlIcon)
                    .lineLimit(1)
            }
            .modifier(NativeProminentButton())
            .controlSize(.large)
            .disabled(model.canToggleQueue == false)
            .help(model.queueControlTitle)

            Button(role: .destructive) {
                model.clearQueue()
            } label: {
                Label("Kuyruğu boşalt", systemImage: "trash")
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.bordered)
            .controlSize(.large)
            .disabled(model.canClearQueue == false)
            .help("Çalışan indirme hariç tüm öğeleri kuyruktan kaldır")
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "tray")
                .font(.system(size: 30))
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)

            Text("Kuyruk boş")
                .font(.headline)

            Text("Eklediğiniz videolar burada görünecek.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func dropTargetBinding(for id: UUID) -> Binding<Bool> {
        Binding(
            get: { dropTargetID == id },
            set: { isTargeted in
                if isTargeted {
                    dropTargetID = id
                } else if dropTargetID == id {
                    dropTargetID = nil
                }
            }
        )
    }

    private var endDropTarget: some View {
        HStack {
            Spacer()
            if draggedItemID != nil || isDroppingAtEnd {
                Label("Sona bırak", systemImage: "arrow.down.to.line")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(isDroppingAtEnd ? Color.accentColor : .secondary)
            }
            Spacer()
        }
        .frame(height: draggedItemID == nil && isDroppingAtEnd == false ? 0 : 36)
        .background(
            Color.accentColor.opacity(isDroppingAtEnd ? 0.16 : 0.06),
            in: RoundedRectangle(cornerRadius: AppControlMetrics.cornerRadius)
        )
    }
}

private struct DownloadQueueRow: View {
    @EnvironmentObject private var model: AppModel
    let item: DownloadItem
    @Binding var draggedItemID: UUID?
    let isDropTarget: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            mediaHeader
            mediaDetails

            if item.subtitles.isEnabled, item.quality.isVideoQuality {
                Label("\(item.subtitles.summary) · \(item.subtitles.delivery.title)", systemImage: "captions.bubble")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .help(item.subtitles.summary)
            }

            if showsProgress {
                ProgressView(value: item.progress)
                    .tint(.accentColor)
                    .accessibilityLabel("İndirme ilerlemesi")
                    .accessibilityValue(DisplayFormatters.percent(item.progress))
            }

            if item.status == .running {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 12) { transferDetails }
                    VStack(alignment: .leading, spacing: 4) { transferDetails }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
            }

            if let error = item.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .help(error)
                    .textSelection(.enabled)
            }

            if let message = item.subtitleMessage {
                Label(message, systemImage: "captions.bubble")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                    .help(message)
                    .textSelection(.enabled)
            }

            Divider()
            statusRow
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            Color(nsColor: .controlBackgroundColor).opacity(0.65),
            in: RoundedRectangle(cornerRadius: AppControlMetrics.cornerRadius)
        )
        .contentShape(RoundedRectangle(cornerRadius: AppControlMetrics.cornerRadius))
        .overlay {
            RoundedRectangle(cornerRadius: AppControlMetrics.cornerRadius)
                .strokeBorder(
                    isDropTarget ? Color.accentColor : Color.primary.opacity(0.08),
                    lineWidth: isDropTarget ? 2 : 1
                )
                .allowsHitTesting(false)
        }
    }

    private var mediaHeader: some View {
        HStack(alignment: .top, spacing: 12) {
            ThumbnailView(url: item.thumbnailURL)
                .frame(width: 88, height: 50)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 6) {
                Text(item.title)
                    .font(.callout.weight(.semibold))
                    .lineLimit(2)
                    .help(item.title)

                Text(formatLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .help(formatLabel)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if model.queue.count > 1 {
                dragHandle
            }
        }
    }

    private var mediaDetails: some View {
        HStack(spacing: 12) {
            Label(audioLanguageTitle, systemImage: "waveform")
                .lineLimit(1)
                .help("Ses dili: \(audioLanguageTitle)")
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(sizeLabel)
                .monospacedDigit()
                .fixedSize()
                .accessibilityLabel("Dosya boyutu: \(sizeLabel)")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    private var statusRow: some View {
        HStack(spacing: 8) {
            Label(item.status.title, systemImage: iconName)
                .font(.caption.weight(.medium))
                .foregroundStyle(iconColor)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(iconColor.opacity(0.10), in: Capsule())
                .fixedSize()

            if showsProgress {
                Text(DisplayFormatters.percent(item.progress))
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            Spacer(minLength: 8)
            rowActions
        }
    }

    private var showsProgress: Bool {
        item.status == .running || (item.status == .pending && item.progress > 0)
    }

    @ViewBuilder
    private var transferDetails: some View {
        if item.speed.isEmpty == false, item.speed != "Unknown", item.speed != "N/A" {
            Text(item.speed)
                .fixedSize(horizontal: true, vertical: false)
                .accessibilityLabel("İndirme hızı \(item.speed)")
        }
        if item.eta.isEmpty == false, item.eta != "Unknown", item.eta != "N/A" {
            Label("Kalan \(item.eta)", systemImage: "clock")
                .fixedSize(horizontal: true, vertical: false)
        }
    }

    private var rowActions: some View {
        HStack(spacing: 6) {
            if model.queue.count > 1 {
                Menu {
                    Button {
                        model.moveQueueItemUp(item)
                    } label: {
                        Label("Yukarı taşı", systemImage: "arrow.up")
                    }
                    .disabled(model.canMoveUp(item) == false)

                    Button {
                        model.moveQueueItemDown(item)
                    } label: {
                        Label("Aşağı taşı", systemImage: "arrow.down")
                    }
                    .disabled(model.canMoveDown(item) == false)
                } label: {
                    Label("Sırayı değiştir", systemImage: "arrow.up.arrow.down")
                }
                .menuIndicator(.hidden)
                .disabled(item.status == .running)
                .help("Kuyruktaki sırayı değiştir")
            }

            if item.status == .failed || item.status == .cancelled {
                Button {
                    model.retry(item)
                } label: {
                    Label("Yeniden dene", systemImage: "arrow.clockwise")
                }
                .help("Yeniden dene")
            }

            if item.outputPath != nil {
                Button {
                    model.revealInFinder(item)
                } label: {
                    Label("Finder’da göster", systemImage: "folder")
                }
                .help("Finder’da göster")
            }

            Button(role: .destructive) {
                model.removeFromQueue(item)
            } label: {
                Label("Kuyruktan kaldır", systemImage: "trash")
            }
            .help(item.status == .completed ? "Kuyruktan kaldır" : "Kuyruktan kaldır ve yarım dosyaları sil")
        }
        .labelStyle(.iconOnly)
        .buttonStyle(.bordered)
        .controlSize(.regular)
    }

    @ViewBuilder
    private var dragHandle: some View {
        if item.status != .running {
            DragHandleView(isEnabled: true)
                .onDrag {
                    draggedItemID = item.id
                    return NSItemProvider(object: item.id.uuidString as NSString)
                }
                .help("Sürükleyerek sırayı değiştir")
        } else {
            DragHandleView(isEnabled: false)
                .help("Çalışan indirme taşınamaz")
        }
    }

    private var iconName: String {
        switch item.status {
        case .pending: return "clock"
        case .running: return "arrow.down.circle"
        case .completed: return "checkmark.circle"
        case .failed: return "exclamationmark.triangle"
        case .cancelled: return "stop.circle"
        }
    }

    private var iconColor: Color {
        switch item.status {
        case .completed: return .green
        case .failed: return .red
        case .running: return .accentColor
        case .pending, .cancelled: return .secondary
        }
    }

    private var formatLabel: String {
        if item.quality.isAudioOnly {
            return "M4A · Yalnızca ses"
        }
        if let format = item.selectedMediaFormat {
            let resolution = format.height.map { "\($0)p" } ?? item.quality.title
            return "\(resolution) · \(format.videoCodecTitle) · \(format.audioCodecTitle) · \(item.container.title)"
        }
        if item.videoCodecPreference == .automatic {
            return "\(item.quality.title) · \(item.container.title)"
        }
        return "\(item.quality.title) · \(item.videoCodecPreference.title) · \(item.container.title)"
    }

    private var sizeLabel: String {
        if let fileSizeBytes = item.fileSizeBytes {
            return ByteCountFormatter.string(fromByteCount: fileSizeBytes, countStyle: .file)
        }
        if let estimatedSizeBytes = item.estimatedSizeBytes {
            return "≈ \(ByteCountFormatter.string(fromByteCount: estimatedSizeBytes, countStyle: .file))"
        }
        return "Boyut bilinmiyor"
    }

    private var audioLanguageTitle: String {
        if let actual = item.selectedMediaFormat?.audioLanguageCode {
            return AudioLanguageSelection(languageCode: actual, isOriginal: item.audioLanguage.isOriginal).title
        }
        return item.audioLanguage.title
    }
}

private struct DragHandleView: View {
    let isEnabled: Bool

    var body: some View {
        Image(systemName: "line.3.horizontal")
            .font(.callout.weight(.semibold))
            .foregroundStyle(.secondary)
            .frame(width: 18, height: 24)
            .contentShape(Rectangle())
            .opacity(isEnabled ? 0.75 : 0.25)
            .accessibilityLabel("Sıralama tutamacı")
    }
}
