import CoreGraphics
import XCTest
@testable import BubbleLogicHost

final class BubbleGeometryTests: XCTestCase {
    func testDefaultIsRightLowerMiddle() {
        let position = BubblePosition.default
        XCTAssertEqual(position.edge, .right)
        XCTAssertEqual(position.normalizedY, 0.72, accuracy: 0.001)
        XCTAssertTrue(position.isValid)
    }

    func testInvalidSavedPositionResets() {
        let position = BubblePosition.restored(edgeRaw: "nope", normalizedY: 4, legacyX: nil, legacyY: nil)
        XCTAssertEqual(position, .default)
    }

    func testLegacyFractionMigratesToEdgeAndNormalizedY() {
        let left = BubblePosition.restored(edgeRaw: nil, normalizedY: nil, legacyX: 0.1, legacyY: 0.4)
        XCTAssertEqual(left.edge, .left)
        XCTAssertEqual(left.normalizedY, 0.4, accuracy: 0.001)
        let right = BubblePosition.restored(edgeRaw: nil, normalizedY: nil, legacyX: 0.9, legacyY: 1.4)
        XCTAssertEqual(right.edge, .right)
        XCTAssertEqual(right.normalizedY, 1, accuracy: 0.001)
    }

    func testStoredEdgeWinsOverLegacyPixels() {
        let position = BubblePosition.restored(edgeRaw: "left", normalizedY: 0.2, legacyX: 0.9, legacyY: 0.9)
        XCTAssertEqual(position.edge, .left)
        XCTAssertEqual(position.normalizedY, 0.2, accuracy: 0.001)
    }

    func testTapOpensAndClosesWithoutDoubleTap() {
        var session = BubbleSession()
        session.tap()
        XCTAssertEqual(session.phase, .expandedPrimary)
        session.tap()
        XCTAssertEqual(session.phase, .collapsed)
    }

    func testDragDoesNotOpenMenu() {
        var session = BubbleSession()
        session.beginDrag()
        session.endDrag(at: CGPoint(x: 20, y: 200), bounds: bounds(size: CGSize(width: 390, height: 844)), snapStrength: 1)
        XCTAssertEqual(session.phase, .collapsed)
        session.tap()
        XCTAssertEqual(session.phase, .collapsed)
        session.tap()
        XCTAssertEqual(session.phase, .expandedPrimary)
    }

    func testOpenMenuCollapsesWhenDragStarts() {
        var session = BubbleSession()
        session.tap()
        session.openNested("hermes")
        XCTAssertEqual(session.phase, .expandedNested("hermes"))
        session.beginDrag()
        XCTAssertEqual(session.phase, .dragging)
        XCTAssertFalse(session.showsBackdrop)
    }

    func testOutsideDismissAndBack() {
        var session = BubbleSession()
        session.tap()
        session.openNested("voice")
        session.back()
        XCTAssertEqual(session.phase, .expandedPrimary)
        session.dismiss()
        XCTAssertEqual(session.phase, .collapsed)
    }

    func testSnapChoosesNearestEdgeAndKeepsY() {
        let wide = bounds(size: CGSize(width: 430, height: 932), top: 59, bottom: 34)
        let left = wide.snapped(CGPoint(x: 30, y: 500), strength: 1)
        XCTAssertEqual(left.edge, .left)
        let right = wide.snapped(CGPoint(x: 400, y: 500), strength: 1)
        XCTAssertEqual(right.edge, .right)
        let center = wide.center(for: right)
        XCTAssertGreaterThan(center.x, 430 / 2)
        XCTAssertGreaterThanOrEqual(center.y, wide.verticalRange().min)
        XCTAssertLessThanOrEqual(center.y, wide.verticalRange().max)
    }

    func testClampStaysInsideSmallAndLargePhones() {
        for size in [CGSize(width: 320, height: 568), CGSize(width: 390, height: 844), CGSize(width: 430, height: 932)] {
            let area = bounds(size: size, top: 47, bottom: 34)
            let clamped = area.clamp(CGPoint(x: -200, y: 5000))
            XCTAssertGreaterThanOrEqual(clamped.x, area.side / 2)
            XCTAssertLessThanOrEqual(clamped.x, size.width - area.side / 2)
            XCTAssertGreaterThanOrEqual(clamped.y, area.verticalRange().min)
            XCTAssertLessThanOrEqual(clamped.y, area.verticalRange().max)
            let placed = area.center(for: .default)
            XCTAssertGreaterThan(placed.x, size.width / 2)
            XCTAssertTrue(CGRect(origin: .zero, size: size).insetBy(dx: -1, dy: -1).contains(placed))
        }
    }

    func testRightEdgeMenuExpandsInwardAndStaysOnScreen() {
        let area = bounds(size: CGSize(width: 390, height: 844), top: 59, bottom: 34)
        let center = area.center(for: BubblePosition(edge: .right, normalizedY: 0.72))
        let menu = area.menuFrame(bubbleCenter: center, menuSize: CGSize(width: 188, height: 320), edge: .right)
        XCTAssertLessThan(menu.midX, center.x)
        XCTAssertLessThanOrEqual(menu.maxX, 390)
        XCTAssertGreaterThanOrEqual(menu.minX, 0)
        XCTAssertGreaterThanOrEqual(menu.minY, 0)
        XCTAssertLessThanOrEqual(menu.maxY, 844)
    }

    func testLeftEdgeMenuExpandsInward() {
        let area = bounds(size: CGSize(width: 390, height: 844), top: 59, bottom: 34)
        let center = area.center(for: BubblePosition(edge: .left, normalizedY: 0.3))
        let menu = area.menuFrame(bubbleCenter: center, menuSize: CGSize(width: 188, height: 280), edge: .left)
        XCTAssertGreaterThan(menu.midX, center.x)
        XCTAssertLessThanOrEqual(menu.maxX, 390)
        XCTAssertGreaterThanOrEqual(menu.minX, 0)
    }

    func testLowBubbleExpandsUpward() {
        let area = bounds(size: CGSize(width: 390, height: 844), top: 59, bottom: 34, bottomObstruction: 0)
        let center = area.center(for: BubblePosition(edge: .right, normalizedY: 0.98))
        let menu = area.menuFrame(bubbleCenter: center, menuSize: CGSize(width: 188, height: 360), edge: .right)
        XCTAssertLessThan(menu.maxY, center.y)
        XCTAssertGreaterThanOrEqual(menu.minY, 0)
        XCTAssertLessThanOrEqual(menu.maxY, 844)
    }

    func testDragFeedbackAndReduceMotion() {
        XCTAssertEqual(bubbleDragScale(isDragging: false), 1, accuracy: 0.001)
        XCTAssertEqual(bubbleDragScale(isDragging: true), 0.94, accuracy: 0.001)
        XCTAssertFalse(bubbleAllowsAnimation(systemReduceMotion: true, preferenceOff: false))
        XCTAssertFalse(bubbleAllowsAnimation(systemReduceMotion: false, preferenceOff: true))
        XCTAssertTrue(bubbleAllowsAnimation(systemReduceMotion: false, preferenceOff: false))
    }

    func testResetReturnsDefault() {
        var session = BubbleSession()
        session.position = BubblePosition(edge: .left, normalizedY: 0.1)
        session.tap()
        session.resetPosition()
        XCTAssertEqual(session.position, .default)
        XCTAssertEqual(session.phase, .collapsed)
    }

    private func bounds(
        size: CGSize,
        top: CGFloat = 20,
        bottom: CGFloat = 0,
        bottomObstruction: CGFloat = 78
    ) -> BubbleSafeBounds {
        BubbleSafeBounds(
            container: size,
            top: top,
            bottom: bottom,
            leading: 0,
            trailing: 0,
            margin: 10,
            bottomObstruction: bottomObstruction,
            side: 52
        )
    }
}
