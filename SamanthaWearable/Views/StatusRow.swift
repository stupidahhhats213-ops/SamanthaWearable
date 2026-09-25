// Views/StatusRow.swift
// Instrument colors matched to the Samantha control-center TUI.

import SwiftUI

enum HUD {
    static let bg = Color(red: 0.035, green: 0.031, blue: 0.024)
    static let panel = Color(red: 0.063, green: 0.051, blue: 0.035)
    static let panel2 = Color(red: 0.090, green: 0.067, blue: 0.035)
    static let ivory = Color(red: 0.933, green: 0.898, blue: 0.835)
    static let muted = Color(red: 0.506, green: 0.459, blue: 0.392)
    static let amber = Color(red: 0.949, green: 0.541, blue: 0.086)
    static let amberDark = Color(red: 0.545, green: 0.333, blue: 0.114)
    static let border = Color(red: 0.239, green: 0.165, blue: 0.090)
    static let red = Color(red: 0.894, green: 0.357, blue: 0.196)
    static let yellow = Color(red: 0.949, green: 0.631, blue: 0.110)
}

struct StatusRow: View {
    let title: String
    let value: String
    var accent: Color = HUD.ivory

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title.uppercased())
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(HUD.muted)
                .frame(width: 118, alignment: .leading)
            Text(value)
                .font(.system(size: 13, weight: .medium, design: .monospaced))
                .foregroundStyle(accent)
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.vertical, 4)
    }
}

struct SectionCard<Content: View>: View {
    let title: String
    var trailing: String? = nil
    var trailingColor: Color = HUD.amber
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Rectangle()
                .fill(HUD.amber)
                .frame(height: 3)
            HStack {
                Text(title)
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundStyle(HUD.amber)
                Spacer()
                if let trailing {
                    Text(trailing)
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundStyle(trailingColor)
                }
            }
            .padding(.horizontal, 14)
            content
                .padding(.horizontal, 14)
                .padding(.bottom, 12)
        }
        .background(HUD.panel)
        .overlay(
            Rectangle()
                .stroke(HUD.border, lineWidth: 1)
        )
    }
}

struct HUDButtonStyle: ButtonStyle {
    var prominent = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .bold, design: .monospaced))
            .foregroundStyle(prominent ? HUD.bg : HUD.ivory)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(prominent ? HUD.amber : HUD.panel2)
            .overlay(Rectangle().stroke(prominent ? HUD.amber : HUD.amberDark, lineWidth: 1))
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

func statusDotColor(_ state: ConnectionState) -> Color {
    switch state {
    case .connected: return HUD.amber
    case .connecting: return HUD.yellow
    case .error: return HUD.red
    case .disconnected: return HUD.muted
    }
}
