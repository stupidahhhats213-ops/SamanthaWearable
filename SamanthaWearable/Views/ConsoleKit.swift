// Views/ConsoleKit.swift
import SwiftUI

struct TerminalPanel<Content: View>: View {
    @EnvironmentObject private var appearance: AppearanceStore
    let title: String
    var trailing: String?
    var sectionID: String = ""
    @ViewBuilder var content: () -> Content

    private var open: Bool { sectionID.isEmpty || !appearance.isCollapsed(sectionID) }

    var body: some View {
        VStack(alignment: .leading, spacing: appearance.rowGap) {
            Button {
                guard !sectionID.isEmpty else { return }
                appearance.toggleSection(sectionID)
            } label: {
                HStack(spacing: 6) {
                    Text("┌─[ \(title) ]")
                        .font(appearance.font(size: 11, weight: .bold))
                        .foregroundStyle(appearance.accent)
                    Spacer(minLength: 8)
                    if let trailing {
                        Text(trailing)
                            .font(appearance.font(size: 10, weight: .bold))
                            .foregroundStyle(appearance.color(appearance.tone(for: trailing)))
                            .lineLimit(1)
                    }
                    if !sectionID.isEmpty {
                        Text(open ? "▾" : "▸")
                            .font(appearance.font(size: 11, weight: .bold))
                            .foregroundStyle(appearance.muted)
                    }
                }
            }
            .buttonStyle(.plain)
            .disabled(sectionID.isEmpty)
            if open {
                content()
                Rectangle()
                    .fill(appearance.border)
                    .frame(height: appearance.lineWidth)
            }
        }
        .padding(appearance.pad)
        .background(appearance.panel)
        .overlay(
            RoundedRectangle(cornerRadius: appearance.radius, style: .continuous)
                .stroke(appearance.border, lineWidth: appearance.lineWidth)
        )
    }
}

struct MetricRow: View {
    @EnvironmentObject private var appearance: AppearanceStore
    let label: String
    let value: String
    var tone: ConsoleTone?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(label.uppercased())
                .font(appearance.font(size: 11, weight: .semibold))
                .foregroundStyle(appearance.muted)
                .frame(width: 78, alignment: .leading)
            Text(value.isEmpty ? "—" : value)
                .font(appearance.font(size: 12, weight: .medium))
                .foregroundStyle(appearance.color(tone ?? appearance.tone(for: value)))
                .frame(maxWidth: .infinity, alignment: .leading)
                .lineLimit(3)
        }
        .padding(.vertical, appearance.density == .compact ? 1 : 3)
        .accessibilityElement(children: .combine)
    }
}

struct GPUBar: View {
    @EnvironmentObject private var appearance: AppearanceStore
    let gpu: GPUReading

    var body: some View {
        HStack(spacing: 8) {
            Text(String(format: "G%-2d", gpu.id))
                .font(appearance.font(size: 12, weight: .bold))
                .foregroundStyle(appearance.text)
                .frame(width: 28, alignment: .leading)
            Text(String(format: "%2.0fC", gpu.temp))
                .font(appearance.font(size: 12, weight: .medium))
                .foregroundStyle(tempTone)
                .frame(width: 36, alignment: .trailing)
            Text(bar)
                .font(appearance.font(size: 11, weight: .regular))
                .foregroundStyle(appearance.accent)
                .frame(width: 72, alignment: .leading)
            Text(String(format: "%3.0f%%", gpu.util))
                .font(appearance.font(size: 12, weight: .medium))
                .foregroundStyle(appearance.text)
                .frame(width: 40, alignment: .trailing)
        }
        .accessibilityLabel("GPU \(gpu.id), \(Int(gpu.temp)) degrees, \(Int(gpu.util)) percent")
    }

    private var bar: String {
        let filled = max(0, min(8, Int((gpu.util / 100 * 8).rounded())))
        return String(repeating: "█", count: filled) + String(repeating: "░", count: 8 - filled)
    }

    private var tempTone: Color {
        if gpu.temp >= 80 { return appearance.error }
        if gpu.temp >= 70 { return appearance.warning }
        return appearance.success
    }
}

struct EventLine: View {
    @EnvironmentObject private var appearance: AppearanceStore
    let event: ConsoleEvent

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(stamp)
                .font(appearance.font(size: 11, weight: .medium))
                .foregroundStyle(appearance.muted)
                .frame(width: 64, alignment: .leading)
            Text(event.channel)
                .font(appearance.font(size: 11, weight: .bold))
                .foregroundStyle(appearance.color(appearance.tone(for: event.channel)))
                .frame(width: 72, alignment: .leading)
            Text(event.message)
                .font(appearance.font(size: 11, weight: .regular))
                .foregroundStyle(appearance.text)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var stamp: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: event.at)
    }
}

struct CommandField: View {
    @EnvironmentObject private var appearance: AppearanceStore
    @Binding var text: String
    var target: String
    var onSubmit: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Text(">")
                .font(appearance.font(size: 14, weight: .bold))
                .foregroundStyle(appearance.accent)
            TextField(target == "HERMES" ? "hermes command" : "samantha command", text: $text)
                .font(appearance.font(size: 13, weight: .medium))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.send)
                .onSubmit(onSubmit)
            Button("RUN", action: onSubmit)
                .font(appearance.font(size: 11, weight: .bold))
                .foregroundStyle(appearance.background)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(appearance.accent)
                .clipShape(RoundedRectangle(cornerRadius: appearance.radius, style: .continuous))
        }
        .padding(.horizontal, appearance.pad)
        .padding(.vertical, 8)
        .background(appearance.panel)
        .overlay(
            RoundedRectangle(cornerRadius: appearance.radius, style: .continuous)
                .stroke(appearance.border, lineWidth: appearance.lineWidth)
        )
    }
}

struct ConsoleButton: View {
    @EnvironmentObject private var appearance: AppearanceStore
    let title: String
    var prominent = false
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(appearance.font(size: 12, weight: .bold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, appearance.density == .compact ? 8 : 11)
                .foregroundStyle(prominent ? appearance.background : appearance.text)
                .background(prominent ? appearance.accent : appearance.panel2)
                .overlay(
                    RoundedRectangle(cornerRadius: appearance.radius, style: .continuous)
                        .stroke(prominent ? appearance.accent : appearance.border, lineWidth: appearance.lineWidth)
                )
                .clipShape(RoundedRectangle(cornerRadius: appearance.radius, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

struct FilterChip: View {
    @EnvironmentObject private var appearance: AppearanceStore
    let title: String
    let selected: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(appearance.font(size: 10, weight: .bold))
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .foregroundStyle(selected ? appearance.background : appearance.muted)
                .background(selected ? appearance.accent : appearance.panel2)
                .overlay(
                    RoundedRectangle(cornerRadius: appearance.radius, style: .continuous)
                        .stroke(appearance.border, lineWidth: appearance.lineWidth)
                )
        }
        .buttonStyle(.plain)
    }
}

struct SamanthaBubbleOverlay: View {
    @EnvironmentObject private var appearance: AppearanceStore
    let size: CGSize
    var bottomObstruction: CGFloat
    @Binding var menuOpen: Bool
    @Binding var nested: String?
    var onAction: (String) -> Void

    @State private var dragging = false
    @State private var pressBegan: Date?
    @State private var origin = CGPoint.zero

    var body: some View {
        let point = bubblePoint
        let side = CGFloat(appearance.bubbleSize)
        let low = point.y > size.height * 0.62
        let showMenu = menuOpen && !dragging
        let onRight = point.x > size.width / 2
        let stackWidth: CGFloat = showMenu ? 176 : side
        let x = onRight ? point.x - stackWidth + side / 2 : point.x - side / 2
        let y = point.y - side / 2 - (showMenu && low ? menuLift : 0)
        return VStack(alignment: onRight ? .trailing : .leading, spacing: 8) {
            if showMenu && low {
                menu
            }
            bubble
                .gesture(drag)
            if showMenu && !low {
                menu
            }
        }
        .offset(x: x, y: y)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Samantha menu")
    }

    private var bubble: some View {
        let side = CGFloat(appearance.bubbleSize)
        return Text("S")
            .font(appearance.font(size: side * 0.42, weight: .bold))
            .foregroundStyle(appearance.background)
            .frame(width: side, height: side)
            .background(appearance.accent.opacity(appearance.bubbleOpacity))
            .clipShape(RoundedRectangle(cornerRadius: max(4, side * 0.22), style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: max(4, side * 0.22), style: .continuous)
                    .stroke(appearance.border, lineWidth: appearance.lineWidth)
            )
            .shadow(color: appearance.accent.opacity(dragging ? 0 : appearance.bubbleGlow), radius: dragging ? 0 : 8)
            .scaleEffect(dragging ? 0.9 : 1)
    }

    private var menu: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let nested {
                Button {
                    self.nested = nil
                } label: {
                    menuRow("BACK", systemImage: "chevron.left")
                }
                .buttonStyle(.plain)
                ForEach(nestedEntries(nested), id: \.0) { entry in
                    Button {
                        onAction(entry.0)
                    } label: {
                        menuRow(entry.1, systemImage: entry.2)
                    }
                    .buttonStyle(.plain)
                }
            } else {
                ForEach(primaryEntries, id: \.0) { entry in
                    Button {
                        nested = entry.0
                    } label: {
                        menuRow(entry.1, systemImage: entry.2)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(8)
        .frame(width: 176, alignment: .leading)
        .background(appearance.panel)
        .overlay(
            RoundedRectangle(cornerRadius: appearance.radius, style: .continuous)
                .stroke(appearance.accent, lineWidth: appearance.lineWidth)
        )
    }

    private var primaryEntries: [(String, String, String)] {
        [
            ("hermes", "HERMES", "terminal"),
            ("voice", "VOICE", "waveform"),
            ("projects", "PROJECTS", "folder"),
            ("system", "SYSTEM", "server.rack"),
            ("logs", "LOGS", "list.bullet.rectangle"),
            ("settings", "SETTINGS", "slider.horizontal.3"),
        ]
    }

    private func nestedEntries(_ id: String) -> [(String, String, String)] {
        switch id {
        case "hermes":
            return [
                ("hermes.open", "OPEN SHELL", "terminal"),
                ("hermes.status", "STATUS", "info.circle"),
                ("hermes.interrupt", "INTERRUPT", "stop.circle"),
                ("hermes.reconnect", "RECONNECT", "arrow.clockwise"),
                ("hermes.restart", "RESTART", "arrow.counterclockwise"),
                ("hermes.logs", "LOGS", "list.bullet"),
            ]
        case "voice":
            return [
                ("voice.wake", "WAKE WORD", "ear"),
                ("voice.mute", "MUTE", "speaker.slash"),
                ("voice.stop", "STOP SPEAKING", "stop.fill"),
                ("voice.route", "AUDIO ROUTE", "hifispeaker"),
                ("voice.page", "VOICE PAGE", "waveform"),
                ("voice.follow", "FOLLOW-UP", "clock"),
            ]
        case "system":
            return [
                ("system.gpus", "GPUS", "square.grid.2x2"),
                ("system.models", "MODELS", "cpu"),
                ("system.services", "SERVICES", "server.rack"),
                ("system.network", "NETWORK", "network"),
                ("system.health", "HEALTH CHECK", "stethoscope"),
                ("system.wearable", "GLASSES", "eyeglasses"),
            ]
        case "projects":
            return [
                ("projects.open", "ACTIVE PROJECT", "folder"),
                ("projects.builds", "BUILDS", "hammer"),
                ("projects.git", "GIT", "arrow.triangle.branch"),
                ("projects.switch", "SWITCH PROJECT", "rectangle.2.swap"),
            ]
        case "logs":
            return [("logs.open", "OPEN LOGS", "list.bullet")]
        case "settings":
            return [
                ("settings.open", "CONNECTION", "link"),
                ("settings.appearance", "APPEARANCE", "paintpalette"),
            ]
        default:
            return []
        }
    }

    private func menuRow(_ title: String, systemImage: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .frame(width: 16)
            Text(title)
                .font(appearance.font(size: 11, weight: .bold))
            Spacer(minLength: 0)
        }
        .foregroundStyle(appearance.text)
        .padding(.vertical, 7)
        .padding(.horizontal, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    private var bubblePoint: CGPoint {
        let side = CGFloat(appearance.bubbleSize)
        let margin: CGFloat = 10
        let x = CGFloat(appearance.bubbleNX) * size.width
        let y = CGFloat(appearance.bubbleNY) * size.height
        return clamp(CGPoint(x: x, y: y), side: side, margin: margin)
    }

    private func clamp(_ point: CGPoint, side: CGFloat, margin: CGFloat) -> CGPoint {
        let half = side / 2
        let minX = half + margin
        let maxX = max(minX, size.width - half - margin)
        let minY = half + margin
        let maxY = max(minY, size.height - half - margin - bottomObstruction)
        return CGPoint(x: min(max(point.x, minX), maxX), y: min(max(point.y, minY), maxY))
    }

    private var menuLift: CGFloat { 220 }

    private var drag: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if pressBegan == nil {
                    pressBegan = Date()
                    origin = bubblePoint
                }
                let held = Date().timeIntervalSince(pressBegan ?? Date()) > 0.28
                let moved = hypot(value.translation.width, value.translation.height) > 12
                guard held || dragging else { return }
                if !dragging {
                    dragging = true
                    menuOpen = false
                    nested = nil
                }
                let next = CGPoint(x: origin.x + value.translation.width, y: origin.y + value.translation.height)
                let clamped = clamp(next, side: CGFloat(appearance.bubbleSize), margin: 10)
                guard size.width > 0, size.height > 0 else { return }
                appearance.persistBubble(nx: clamped.x / size.width, ny: clamped.y / size.height)
                _ = moved
            }
            .onEnded { value in
                let moved = hypot(value.translation.width, value.translation.height) > 12
                let held = Date().timeIntervalSince(pressBegan ?? Date()) > 0.28
                defer { pressBegan = nil }
                if dragging || (held && moved) {
                    snap(from: bubblePoint)
                    dragging = false
                } else if !moved {
                    toggleMenu()
                }
                dragging = false
            }
    }

    private func toggleMenu() {
        let change = {
            if menuOpen {
                menuOpen = false
                nested = nil
            } else {
                menuOpen = true
            }
        }
        if appearance.motionAmount == 0 {
            change()
        } else {
            withAnimation(.easeOut(duration: 0.18)) { change() }
        }
    }

    private func snap(from point: CGPoint) {
        let side = CGFloat(appearance.bubbleSize)
        let margin: CGFloat = 10
        let half = side / 2
        let left = half + margin
        let right = max(left, size.width - half - margin)
        let strength = appearance.snapStrength
        let targetX = abs(point.x - left) < abs(point.x - right) ? left : right
        let x = point.x + (targetX - point.x) * strength
        let clamped = clamp(CGPoint(x: x, y: point.y), side: side, margin: margin)
        guard size.width > 0, size.height > 0 else { return }
        let apply = {
            appearance.persistBubble(nx: clamped.x / size.width, ny: clamped.y / size.height)
        }
        if appearance.motionAmount == 0 {
            apply()
        } else {
            withAnimation(.easeOut(duration: 0.16)) { apply() }
        }
    }
}
