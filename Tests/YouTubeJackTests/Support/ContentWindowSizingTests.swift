import Foundation
import Testing
@testable import YouTubeJack

struct ContentWindowSizingTests {
    private let original = CGRect(x: 100, y: 200, width: 1160, height: 740)
    private let screen = CGRect(x: 0, y: 0, width: 1728, height: 1100)

    @Test
    func openingAndClosingFitsContentWithoutChangingWidthOrTheTopEdge() throws {
        var state = ContentWindowHeightState()
        let expandedCandidate = state.targetFrame(
            for: layout(height: 568, viewport: 501), windowFrame: original, minimumHeight: 680, visibleFrame: screen
        )
        let expanded = try #require(expandedCandidate)
        #expect(expanded.height == 808)
        #expect(expanded.width == original.width)
        #expect(expanded.maxY == original.maxY)
        let collapsedCandidate = state.targetFrame(
            for: layout(height: 500, viewport: 569), windowFrame: expanded, minimumHeight: 680, visibleFrame: screen
        )
        let collapsed = try #require(collapsedCandidate)
        #expect(collapsed == original)
    }

    @Test
    func overflowGrowsTheWindowBeforeRequiringScroll() throws {
        var state = ContentWindowHeightState()
        let fittedCandidate = state.targetFrame(
            for: layout(height: 700, viewport: 500), windowFrame: original, minimumHeight: 680, visibleFrame: screen
        )
        let fitted = try #require(fittedCandidate)
        #expect(fitted.height == 941)
        #expect(fitted.width == 1160)
        #expect(fitted.minY >= screen.minY)
        #expect(fitted.maxY <= screen.maxY)
    }

    @Test
    func screenLimitRetainsOverflowAndClosingStillRestoresTheHeight() throws {
        var state = ContentWindowHeightState()
        let smallerScreen = CGRect(x: 0, y: 0, width: 1440, height: 760)
        let expandedCandidate = state.targetFrame(
            for: layout(height: 568, viewport: 501), windowFrame: original, minimumHeight: 680, visibleFrame: smallerScreen
        )
        let expanded = try #require(expandedCandidate)
        #expect(expanded.height == 760)
        #expect(expanded.minY == smallerScreen.minY)
        let collapsedCandidate = state.targetFrame(
            for: layout(height: 500, viewport: 521), windowFrame: expanded, minimumHeight: 680, visibleFrame: smallerScreen
        )
        let collapsed = try #require(collapsedCandidate)
        #expect(collapsed.height == original.height)
        #expect(collapsed.width == original.width)
    }

    @Test
    func viewportOnlyChangesDoNotUndoManualResizing() {
        var state = ContentWindowHeightState()
        _ = state.targetFrame(for: layout(height: 500, viewport: 501), windowFrame: original, minimumHeight: 680, visibleFrame: screen)
        let taller = CGRect(x: 100, y: 100, width: 1160, height: 840)
        #expect(state.targetFrame(
            for: layout(height: 500, viewport: 601), windowFrame: taller, minimumHeight: 680, visibleFrame: screen
        ) == nil)
    }

    @Test
    func shortContentKeepsTheWindowMinimum() throws {
        var state = ContentWindowHeightState()
        let fittedCandidate = state.targetFrame(
            for: layout(height: 180, viewport: 501), windowFrame: original, minimumHeight: 680, visibleFrame: screen
        )
        let fitted = try #require(fittedCandidate)
        #expect(fitted.height == 680)
    }

    private func layout(height: CGFloat, viewport: CGFloat) -> MainContentLayout {
        MainContentLayout(contentSize: CGSize(width: 684, height: height), viewportHeight: viewport)
    }
}
