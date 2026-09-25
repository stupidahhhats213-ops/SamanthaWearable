// Bubble/SamanthaBubble.swift
import SwiftUI

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
            .accessibilityIdentifier("samanthaBubble")
            .accessibilityLabel("Samantha menu")
            .accessibilityAddTraits(.isButton)
    }
}
