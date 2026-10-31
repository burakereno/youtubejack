import AppKit
import SwiftUI

struct MainContentLayout: Equatable {
    var contentSize = CGSize.zero
    var viewportHeight: CGFloat = 0
}

struct MainContentLayoutKey: PreferenceKey {
    static let defaultValue = MainContentLayout()

    static func reduce(value: inout MainContentLayout, nextValue: () -> MainContentLayout) {
        let next = nextValue()
        if next.contentSize.height > 0 { value.contentSize = next.contentSize }
        if next.viewportHeight > 0 { value.viewportHeight = next.viewportHeight }
    }
}

struct ContentWindowHeightState {
    private var previousContentSize: CGSize?

    mutating func targetFrame(
        for layout: MainContentLayout,
        windowFrame: CGRect,
        minimumHeight: CGFloat,
        visibleFrame: CGRect
    ) -> CGRect? {
        guard layout.contentSize.height > 0, layout.viewportHeight > 0 else { return nil }
        // A manual height change alone should not snap the window back.
        guard layout.contentSize != previousContentSize else { return nil }
        previousContentSize = layout.contentSize

        // The current frame/viewport difference includes the toolbar, URL bar and pinned controls.
        // One point of spare space prevents a scrollbar from fractional layout rounding.
        let fittedHeight = ceil(windowFrame.height + layout.contentSize.height - layout.viewportHeight + 1)
        let height = min(visibleFrame.height, max(minimumHeight, fittedHeight))
        guard abs(height - windowFrame.height) > 0.5 else { return nil }

        var frame = windowFrame
        frame.size.height = height
        frame.origin.y = max(visibleFrame.minY, min(windowFrame.maxY - height, visibleFrame.maxY - height))
        return frame
    }
}

/// Fits the scrolling content vertically; SwiftUI continues to own the layout and window width.
struct ContentWindowSizing: NSViewRepresentable {
    let layout: MainContentLayout

    func makeNSView(context: Context) -> SizingView {
        SizingView()
    }

    func updateNSView(_ nsView: SizingView, context: Context) {
        nsView.contentLayout = layout
        nsView.scheduleResize()
    }

    final class SizingView: NSView {
        var contentLayout = MainContentLayout()
        private var heightState = ContentWindowHeightState()
        private var isResizeScheduled = false

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            scheduleResize()
        }

        func scheduleResize() {
            guard isResizeScheduled == false else { return }
            isResizeScheduled = true
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.isResizeScheduled = false
                self.resizeIfNeeded()
            }
        }

        private func resizeIfNeeded() {
            guard let window, let screen = window.screen else { return }
            guard window.styleMask.contains(.fullScreen) == false else {
                heightState = ContentWindowHeightState()
                return
            }
            guard let frame = heightState.targetFrame(
                for: contentLayout,
                windowFrame: window.frame,
                minimumHeight: window.minSize.height,
                visibleFrame: screen.visibleFrame
            ) else { return }

            window.setFrame(
                frame,
                display: true,
                animate: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion == false
            )
        }
    }
}
