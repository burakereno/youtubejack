import SwiftUI
import UniformTypeIdentifiers
import YouTubeJackCore

struct QueueView: View {
    @EnvironmentObject private var model: AppModel
    @State private var draggedItemID: UUID?
    @State private var dropTargetID: UUID?
    @State private var isDroppingAtEnd = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Kuyruk")
                    .font(.headline)

                if model.queue.isEmpty == false {
                    Text("\(model.queue.count) öğe")
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    model.clearQueue()
                } label: {
                    Label("Kuyruğu Boşalt", systemImage: "trash")
                }
                .disabled(model.canClearQueue == false)
                .help("Çalışan indirme hariç tüm öğeleri kuyruktan kaldır")
            }

	            if model.queue.isEmpty {
	                Text("Kuyruk boş")
	                    .foregroundStyle(.secondary)
	                    .frame(maxWidth: .infinity, maxHeight: .infinity)
	                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
	            } else {
	                ScrollView {
	                    VStack(spacing: 0) {
	                        ForEach(model.queue) { item in
	                            DownloadQueueRow(
	                                item: item,
	                                draggedItemID: $draggedItemID,
	                                isDropTarget: dropTargetID == item.id
	                            )
	                                .environmentObject(model)
	                                .opacity(draggedItemID == item.id ? 0.62 : 1)
	                                .onDrop(of: [UTType.text], isTargeted: dropTargetBinding(for: item.id)) { _ in
	                                    guard let draggedItemID else { return false }
	                                    model.moveQueueItem(draggedID: draggedItemID, before: item.id)
	                                    self.draggedItemID = nil
	                                    self.dropTargetID = nil
	                                    return true
	                                }
	                            if item.id != model.queue.last?.id {
	                                Divider()
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
	                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
	            }
	        }
	        .frame(maxHeight: .infinity, alignment: .top)
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
                    .foregroundStyle(isDroppingAtEnd ? .orange : .secondary)
            }
            Spacer()
        }
        .frame(height: draggedItemID == nil && isDroppingAtEnd == false ? 8 : 34)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isDroppingAtEnd ? Color.orange.opacity(0.18) : Color.clear)
        )
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
    }
	}

private struct DownloadQueueRow: View {
    @EnvironmentObject private var model: AppModel
    let item: DownloadItem
    @Binding var draggedItemID: UUID?
    let isDropTarget: Bool

    var body: some View {
        HStack(spacing: 12) {
            dragHandle

            ThumbnailView(url: item.thumbnailURL)
                .frame(width: 92, height: 52)
                .overlay(alignment: .bottomTrailing) {
                    QueueStatusBadge(systemImage: iconName, color: iconColor)
                        .padding(4)
                }

            VStack(alignment: .leading, spacing: 6) {
                Text(item.title)
                    .font(.callout.weight(.semibold))
                    .lineLimit(1)

                HStack(spacing: 5) {
                    Text(formatLabel)
                    Text("•")
                    Text(sizeLabel)
                }
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)

                ProgressView(value: item.progress)
                    .opacity(item.status == .running || item.status == .completed ? 1 : 0.35)

                HStack(spacing: 8) {
                    Text(item.status.title)
                    if item.speed.isEmpty == false {
                        Text(item.speed)
                    }
                    if item.eta.isEmpty == false, item.eta != "Unknown" {
                        Text("ETA \(item.eta)")
                    }
                    if let error = item.errorMessage {
                        Text(error)
                            .lineLimit(1)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer()

            if item.status == .failed || item.status == .cancelled {
                Button {
                    model.retry(item)
                } label: {
                    Label("Yeniden Dene", systemImage: "arrow.clockwise")
                }
                .labelStyle(.iconOnly)
                .help("Yeniden dene")
            }

            Button {
                model.removeFromQueue(item)
            } label: {
                Label("Sil", systemImage: "trash")
            }
            .labelStyle(.iconOnly)
            .help(item.status == .completed ? "Kuyruktan kaldır" : "Kuyruktan kaldır ve yarım dosyaları sil")

            if item.outputPath != nil {
                Button {
                    model.revealInFinder(item)
                } label: {
                    Label("Finder", systemImage: "magnifyingglass")
                }
                .labelStyle(.iconOnly)
                .help("Finder'da göster")
            }
        }
        .padding(12)
        .contentShape(Rectangle())
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isDropTarget ? Color.orange.opacity(0.12) : Color.clear)
        )
        .overlay(alignment: .top) {
            if isDropTarget {
                Capsule()
                    .fill(Color.orange.opacity(0.85))
                    .frame(height: 3)
                    .padding(.horizontal, 12)
            }
        }
    }

    @ViewBuilder
    private var dragHandle: some View {
        let canDrag = item.status != .running && model.queue.count > 1
        if canDrag {
            DragHandleView(isEnabled: true)
                .onDrag {
                    draggedItemID = item.id
                    return NSItemProvider(object: item.id.uuidString as NSString)
                }
                .help("Sürükleyerek sırayı değiştir")
        } else {
            DragHandleView(isEnabled: false)
                .help(item.status == .running ? "Çalışan indirme taşınamaz" : "Taşımak için en az iki öğe gerekir")
        }
    }

    private var iconName: String {
        switch item.status {
        case .pending:
            return "clock"
        case .running:
            return "arrow.down.circle"
        case .completed:
            return "checkmark.circle"
        case .failed:
            return "exclamationmark.triangle"
        case .cancelled:
            return "stop.circle"
        }
    }

    private var iconColor: Color {
        switch item.status {
        case .completed:
            return .green
        case .failed:
            return .red
        case .cancelled:
            return .secondary
        case .running:
            return .accentColor
        case .pending:
            return .secondary
        }
    }

    private var formatLabel: String {
        if item.quality.isAudioOnly {
            return "\(item.quality.title) · M4A"
        }
        return "\(item.quality.title) · \(item.container.title)"
    }

    private var sizeLabel: String {
        if let fileSizeBytes = item.fileSizeBytes {
            return DisplayFormatters.fileSize(fileSizeBytes)
        }
        if let estimatedSizeBytes = item.estimatedSizeBytes {
            return "~\(DisplayFormatters.fileSize(estimatedSizeBytes))"
        }
        return "Boyut bilinmiyor"
    }
}

private struct DragHandleView: View {
    let isEnabled: Bool

    var body: some View {
        Image(systemName: "line.3.horizontal")
            .font(.title3.weight(.semibold))
            .foregroundStyle(.secondary)
            .frame(width: 22, height: 42)
            .opacity(isEnabled ? 0.85 : 0.25)
    }
}

private struct QueueStatusBadge: View {
    let systemImage: String
    let color: Color

    var body: some View {
        Image(systemName: systemImage)
            .font(.caption.weight(.bold))
            .foregroundStyle(.white)
            .frame(width: 22, height: 22)
            .background(color, in: Circle())
            .overlay(
                Circle()
                    .stroke(.black.opacity(0.18), lineWidth: 1)
            )
    }
}
