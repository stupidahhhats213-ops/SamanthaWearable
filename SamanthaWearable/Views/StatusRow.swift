// Views/StatusRow.swift
import SwiftUI

struct StatusRow: View {
    let title: String
    let value: String
    var accent: Color = Color(red: 0.95, green: 0.54, blue: 0.0)

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title.uppercased())
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(Color(white: 0.55))
                .frame(width: 110, alignment: .leading)
            Text(value)
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .foregroundStyle(accent)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.vertical, 3)
    }
}

struct SectionCard<Content: View>: View {
    let title: String
    var trailing: String? = nil
    var trailingColor: Color = Color(red: 0.95, green: 0.54, blue: 0.0)
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundStyle(Color(red: 0.95, green: 0.54, blue: 0.0))
                Spacer()
                if let trailing {
                    Text(trailing)
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundStyle(trailingColor)
                }
            }
            content
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(red: 0.06, green: 0.05, blue: 0.035))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color(red: 0.24, green: 0.16, blue: 0.09), lineWidth: 1)
                )
        )
    }
}

func statusDotColor(_ state: ConnectionState) -> Color {
    switch state {
    case .connected: return Color(red: 0.95, green: 0.54, blue: 0.0)
    case .connecting: return Color(red: 0.95, green: 0.63, blue: 0.11)
    case .error: return Color(red: 0.89, green: 0.36, blue: 0.20)
    case .disconnected: return Color(white: 0.45)
    }
}
