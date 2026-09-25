// Bubble/BubbleGeometry.swift
// Pure layout and gesture state. No SwiftUI, so the logic tests do not need the app.

import CoreGraphics
import Foundation

enum BubbleEdge: String, Equatable {
    case left
    case right
}

enum BubblePhase: Equatable {
    case collapsed
    case expandedPrimary
    case expandedNested(String)
    case dragging
}

struct BubblePosition: Equatable {
    var edge: BubbleEdge
    var normalizedY: Double

    static let `default` = BubblePosition(edge: .right, normalizedY: 0.72)

    var isValid: Bool {
        normalizedY.isFinite && normalizedY >= 0 && normalizedY <= 1
    }

    static func restored(edgeRaw: String?, normalizedY: Double?, legacyX: Double?, legacyY: Double?) -> BubblePosition {
        if let edgeRaw, let edge = BubbleEdge(rawValue: edgeRaw), let normalizedY, normalizedY.isFinite, normalizedY >= 0, normalizedY <= 1 {
            return BubblePosition(edge: edge, normalizedY: normalizedY)
        }
        if let legacyY, legacyY.isFinite {
            let edge: BubbleEdge = (legacyX ?? 1) < 0.5 ? .left : .right
            let y = min(1, max(0, legacyY))
            return BubblePosition(edge: edge, normalizedY: y)
        }
        return .default
    }
}

struct BubbleSafeBounds: Equatable {
    var container: CGSize
    var top: CGFloat
    var bottom: CGFloat
    var leading: CGFloat
    var trailing: CGFloat
    var margin: CGFloat
    var bottomObstruction: CGFloat
    var side: CGFloat

    func verticalRange() -> (min: CGFloat, max: CGFloat) {
        let half = side / 2
        let minY = top + half + margin
        let maxY = container.height - bottom - half - margin - bottomObstruction
        if maxY >= minY {
            return (minY, maxY)
        }
        let mid = max(half, min(container.height - half, container.height / 2))
        return (mid, mid)
    }

    func center(for position: BubblePosition) -> CGPoint {
        let range = verticalRange()
        let y = range.min + (range.max - range.min) * CGFloat(min(1, max(0, position.normalizedY)))
        let half = side / 2
        let x: CGFloat
        if position.edge == .left {
            x = leading + half + margin
        } else {
            x = container.width - trailing - half - margin
        }
        return clamp(CGPoint(x: x, y: y))
    }

    func clamp(_ point: CGPoint) -> CGPoint {
        let range = verticalRange()
        let half = side / 2
        let minX = leading + half + margin
        let maxX = max(minX, container.width - trailing - half - margin)
        return CGPoint(
            x: min(max(point.x, minX), maxX),
            y: min(max(point.y, range.min), range.max)
        )
    }

    func snapped(_ point: CGPoint, strength: Double) -> BubblePosition {
        let clamped = clamp(point)
        let edge: BubbleEdge = clamped.x < container.width / 2 ? .left : .right
        let range = verticalRange()
        let span = max(range.max - range.min, 1)
        let along = Double((clamped.y - range.min) / span)
        let y = min(1, max(0, along.isFinite ? along : 0.72))
        _ = strength
        let resolved = BubblePosition(edge: edge, normalizedY: y)
        return resolved.isValid ? resolved : .default
    }

    func menuFrame(bubbleCenter: CGPoint, menuSize: CGSize, edge: BubbleEdge) -> CGRect {
        let bubble = CGRect(
            x: bubbleCenter.x - side / 2,
            y: bubbleCenter.y - side / 2,
            width: side,
            height: side
        )
        let gap: CGFloat = 8
        var originX = edge == .right ? bubble.maxX - menuSize.width : bubble.minX
        let roomBelow = container.height - bottom - margin - bubble.maxY
        let roomAbove = bubble.minY - top - margin
        let expandUp = roomBelow < menuSize.height + gap && roomAbove > roomBelow
        var originY = expandUp ? bubble.minY - gap - menuSize.height : bubble.maxY + gap
        let minX = leading + margin
        let maxX = container.width - trailing - margin - menuSize.width
        let minY = top + margin
        let maxY = container.height - bottom - margin - menuSize.height
        originX = min(max(originX, minX), max(minX, maxX))
        originY = min(max(originY, minY), max(minY, maxY))
        return CGRect(x: originX, y: originY, width: menuSize.width, height: menuSize.height)
    }
}

struct BubbleSession: Equatable {
    var phase: BubblePhase = .collapsed
    var position: BubblePosition = .default
    var suppressTap = false

    var showsBackdrop: Bool {
        switch phase {
        case .expandedPrimary, .expandedNested:
            return true
        case .collapsed, .dragging:
            return false
        }
    }

    mutating func tap() {
        if suppressTap {
            suppressTap = false
            return
        }
        switch phase {
        case .collapsed:
            phase = .expandedPrimary
        case .expandedPrimary, .expandedNested:
            phase = .collapsed
        case .dragging:
            break
        }
    }

    mutating func beginDrag() {
        phase = .dragging
        suppressTap = true
    }

    mutating func endDrag(at point: CGPoint, bounds: BubbleSafeBounds, snapStrength: Double) {
        position = bounds.snapped(point, strength: snapStrength)
        phase = .collapsed
        suppressTap = true
    }

    mutating func dismiss() {
        if phase != .dragging {
            phase = .collapsed
        }
    }

    mutating func openNested(_ id: String) {
        guard phase == .expandedPrimary || phase.isNested else { return }
        phase = .expandedNested(id)
    }

    mutating func back() {
        if case .expandedNested = phase {
            phase = .expandedPrimary
        }
    }

    mutating func resetPosition() {
        position = .default
        phase = .collapsed
        suppressTap = false
    }
}

extension BubblePhase {
    var isNested: Bool {
        if case .expandedNested = self { return true }
        return false
    }

    var nestedID: String? {
        if case .expandedNested(let id) = self { return id }
        return nil
    }
}

func bubbleDragScale(isDragging: Bool) -> CGFloat {
    isDragging ? 0.94 : 1
}

func bubbleAllowsAnimation(systemReduceMotion: Bool, preferenceOff: Bool) -> Bool {
    !systemReduceMotion && !preferenceOff
}
