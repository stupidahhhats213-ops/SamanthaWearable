// Bubble/SamanthaBubble.swift
import SwiftUI
import UIKit

struct SamanthaBubbleButton: View {
    @EnvironmentObject private var appearance: AppearanceStore
    var isDragging: Bool

    var body: some View {
        let side = max(44, CGFloat(appearance.bubbleSize))
        Text("S")
            .font(appearance.font(size: side * 0.42, weight: .bold))
            .foregroundStyle(appearance.background)
            .frame(width: side, height: side)
            .background(appearance.accent.opacity(isDragging ? appearance.bubbleOpacity * 0.82 : appearance.bubbleOpacity))
            .clipShape(RoundedRectangle(cornerRadius: max(4, side * 0.22), style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: max(4, side * 0.22), style: .continuous)
                    .stroke(appearance.border, lineWidth: max(appearance.lineWidth, 1))
            )
            .shadow(color: appearance.accent.opacity(isDragging ? 0 : appearance.bubbleGlow), radius: isDragging ? 0 : 8)
            .scaleEffect(bubbleDragScale(isDragging: isDragging))
            .contentShape(Rectangle())
    }
}

struct BubbleGesturePad: UIViewRepresentable {
    var onTap: () -> Void
    var onDragBegan: () -> Void
    var onDragChanged: (CGSize) -> Void
    var onDragEnded: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .clear
        view.isAccessibilityElement = true
        view.accessibilityIdentifier = "samanthaBubble"
        view.accessibilityLabel = "Samantha menu"
        view.accessibilityTraits = [.button]
        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.tapped))
        let press = UILongPressGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.pressed(_:)))
        press.minimumPressDuration = 0.32
        press.allowableMovement = 16
        tap.require(toFail: press)
        view.addGestureRecognizer(tap)
        view.addGestureRecognizer(press)
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.onTap = onTap
        context.coordinator.onDragBegan = onDragBegan
        context.coordinator.onDragChanged = onDragChanged
        context.coordinator.onDragEnded = onDragEnded
    }

    final class Coordinator: NSObject {
        var onTap: () -> Void = {}
        var onDragBegan: () -> Void = {}
        var onDragChanged: (CGSize) -> Void = { _ in }
        var onDragEnded: () -> Void = {}
        private var start = CGPoint.zero

        @objc func tapped() {
            onTap()
        }

        @objc func pressed(_ gesture: UILongPressGestureRecognizer) {
            let point = gesture.location(in: gesture.view?.window)
            switch gesture.state {
            case .began:
                start = point
                onDragBegan()
            case .changed:
                onDragChanged(CGSize(width: point.x - start.x, height: point.y - start.y))
            case .ended, .cancelled:
                onDragEnded()
            default:
                break
            }
        }
    }
}
