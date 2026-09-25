// Bubble/BubbleOverlay.swift
import SwiftUI
import UIKit

@MainActor
final class SamanthaBubbleModel: ObservableObject {
    @Published var phase: BubblePhase = .collapsed
    @Published var dragCenter: CGPoint?
    private var session = BubbleSession()
    private var anchor = CGPoint.zero

    var showsBackdrop: Bool { session.showsBackdrop }
    var nestedID: String? { phase.nestedID }

    func syncPosition(from appearance: AppearanceStore) {
        session.position = BubblePosition.restored(
            edgeRaw: appearance.bubbleEdgeRaw,
            normalizedY: appearance.bubbleNormalizedY,
            legacyX: appearance.bubbleNX,
            legacyY: appearance.bubbleNY
        )
        objectWillChange.send()
    }

    func renderedCenter(bounds: BubbleSafeBounds) -> CGPoint {
        if phase == .dragging, let dragCenter {
            return bounds.clamp(dragCenter)
        }
        return bounds.center(for: session.position)
    }

    func tap() {
        let before = session.phase
        session.tap()
        phase = session.phase
        if session.phase == .expandedPrimary && before == .collapsed {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
    }

    func dismiss() {
        session.dismiss()
        phase = session.phase
    }

    func openNested(_ id: String) {
        session.openNested(id)
        phase = session.phase
    }

    func back() {
        session.back()
        phase = session.phase
    }

    func beginDrag(at center: CGPoint) {
        anchor = center
        dragCenter = center
        session.beginDrag()
        phase = session.phase
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    func follow(translation: CGSize, bounds: BubbleSafeBounds) {
        guard phase == .dragging else { return }
        dragCenter = bounds.clamp(CGPoint(x: anchor.x + translation.width, y: anchor.y + translation.height))
    }

    func endDrag(bounds: BubbleSafeBounds, appearance: AppearanceStore) {
        let point = dragCenter ?? bounds.center(for: session.position)
        session.endDrag(at: point, bounds: bounds, snapStrength: appearance.snapStrength)
        phase = session.phase
        dragCenter = nil
        appearance.setBubbleEdge(session.position.edge.rawValue)
        appearance.setBubbleNormalizedY(session.position.normalizedY)
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    func applyExternalReset(appearance: AppearanceStore) {
        session.resetPosition()
        phase = .collapsed
        dragCenter = nil
        appearance.setBubbleEdge(BubblePosition.default.edge.rawValue)
        appearance.setBubbleNormalizedY(BubblePosition.default.normalizedY)
    }
}

struct BubbleOverlay: View {
    @EnvironmentObject private var appearance: AppearanceStore
    @ObservedObject var model: SamanthaBubbleModel
    var container: CGSize
    var safeTop: CGFloat
    var safeBottom: CGFloat
    var safeLeading: CGFloat
    var safeTrailing: CGFloat
    var bottomObstruction: CGFloat
    var onAction: (String) -> Void

    var body: some View {
        let bounds = currentBounds
        let center = model.renderedCenter(bounds: bounds)
        let menuSize = CGSize(width: 188, height: menuHeight)
        let menuRect = bounds.menuFrame(
            bubbleCenter: center,
            menuSize: menuSize,
            edge: center.x < container.width / 2 ? .left : .right
        )
        let bubbleRect = CGRect(x: center.x - bubbleSide / 2, y: center.y - bubbleSide / 2, width: bubbleSide, height: bubbleSide)
        ZStack(alignment: .topLeading) {
            if model.showsBackdrop {
                Color.clear
                    .frame(width: container.width, height: container.height)
                    .contentShape(Rectangle())
                    .onTapGesture { animate { model.dismiss() } }
                    .accessibilityIdentifier("bubbleBackdrop")
                    .accessibilityLabel("Dismiss Samantha menu")
            }
            if model.showsBackdrop {
                BubbleMenu(
                    items: menuItems,
                    showsBack: model.nestedID != nil,
                    onBack: { animate { model.back() } },
                    onCollapse: { animate { model.dismiss() } },
                    onSelect: select
                )
                .offset(x: menuRect.minX, y: menuRect.minY)
                .zIndex(2)
            }
            SamanthaBubbleButton(isDragging: model.phase == .dragging)
                .overlay(
                    BubbleGesturePad(
                        onTap: { animate { model.tap() } },
                        onDragBegan: { model.beginDrag(at: center) },
                        onDragChanged: { model.follow(translation: $0, bounds: bounds) },
                        onDragEnded: {
                            guard model.phase == .dragging else { return }
                            let apply = { model.endDrag(bounds: bounds, appearance: appearance) }
                            if bubbleAllowsAnimation(systemReduceMotion: UIAccessibility.isReduceMotionEnabled, preferenceOff: appearance.motion == .off) {
                                withAnimation(.easeOut(duration: 0.16)) { apply() }
                            } else {
                                apply()
                            }
                        }
                    )
                )
                .offset(x: bubbleRect.minX, y: bubbleRect.minY)
                .zIndex(3)
        }
        .frame(width: container.width, height: container.height, alignment: .topLeading)
        .contentShape(
            model.showsBackdrop
                ? BubbleTouchShape(bubble: CGRect(origin: .zero, size: container), menu: menuRect)
                : BubbleTouchShape(bubble: bubbleRect, menu: nil)
        )
        .onAppear { model.syncPosition(from: appearance) }
        .onChange(of: appearance.bubbleEdgeRaw) { _, _ in
            guard model.phase != .dragging else { return }
            model.syncPosition(from: appearance)
        }
        .onChange(of: appearance.bubbleNormalizedY) { _, _ in
            guard model.phase != .dragging else { return }
            model.syncPosition(from: appearance)
        }
    }

    private var bubbleSide: CGFloat { max(44, CGFloat(appearance.bubbleSize)) }

    private var currentBounds: BubbleSafeBounds {
        BubbleSafeBounds(
            container: container,
            top: safeTop,
            bottom: safeBottom,
            leading: safeLeading,
            trailing: safeTrailing,
            margin: 10,
            bottomObstruction: model.showsBackdrop ? 0 : bottomObstruction,
            side: bubbleSide
        )
    }

    private var menuItems: [BubbleMenuItem] {
        if let nested = model.nestedID {
            return BubbleMenus.nested(nested)
        }
        return BubbleMenus.primary
    }

    private var menuHeight: CGFloat {
        let back = model.nestedID == nil ? 0 : 1
        let rows = CGFloat(menuItems.count + 1 + back)
        return rows * 44 + 16
    }

    private func select(_ id: String) {
        if id == "settings" {
            model.dismiss()
            onAction("settings.open")
            return
        }
        if model.nestedID == nil && BubbleMenus.nested(id).isEmpty == false && !id.contains(".") {
            animate { model.openNested(id) }
            return
        }
        model.dismiss()
        onAction(id)
    }

    private func animate(_ change: () -> Void) {
        let reduced = appearance.motion == .reduced
        let allowed = bubbleAllowsAnimation(
            systemReduceMotion: UIAccessibility.isReduceMotionEnabled,
            preferenceOff: appearance.motion == .off
        )
        if !allowed {
            change()
        } else {
            withAnimation(.easeOut(duration: reduced ? 0.08 : 0.16)) { change() }
        }
    }
}

struct BubbleTouchShape: Shape {
    var bubble: CGRect
    var menu: CGRect?

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.addRect(bubble.insetBy(dx: -6, dy: -6))
        if let menu {
            path.addRect(menu.insetBy(dx: -4, dy: -4))
        }
        return path
    }
}
