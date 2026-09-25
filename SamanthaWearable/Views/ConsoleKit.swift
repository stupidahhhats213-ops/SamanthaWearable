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
