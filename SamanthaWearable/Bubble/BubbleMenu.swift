// Bubble/BubbleMenu.swift
import SwiftUI

struct BubbleMenuItem: Identifiable {
    let id: String
    let title: String
    let systemImage: String
    let accessibilityID: String
    let accessibilityLabel: String
}

struct BubbleMenu: View {
    @EnvironmentObject private var appearance: AppearanceStore
    var items: [BubbleMenuItem]
    var showsBack: Bool
    var onBack: () -> Void
    var onCollapse: () -> Void
    var onSelect: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if showsBack {
                rowButton(
                    id: "back",
                    title: "BACK",
                    systemImage: "chevron.left",
                    accessibilityID: "bubbleBack",
                    accessibilityLabel: "Back"
                ) {
                    onBack()
                }
            }
            ForEach(items) { item in
                rowButton(
                    id: item.id,
                    title: item.title,
                    systemImage: item.systemImage,
                    accessibilityID: item.accessibilityID,
                    accessibilityLabel: item.accessibilityLabel
                ) {
                    onSelect(item.id)
                }
            }
            rowButton(
                id: "collapse",
                title: "COLLAPSE",
                systemImage: "xmark",
                accessibilityID: "bubbleCollapse",
                accessibilityLabel: "Collapse"
            ) {
                onCollapse()
            }
        }
        .padding(8)
        .frame(width: 188, alignment: .leading)
        .background(appearance.panel)
        .overlay(
            RoundedRectangle(cornerRadius: appearance.radius, style: .continuous)
                .stroke(appearance.accent, lineWidth: max(appearance.lineWidth, 1))
        )
        .accessibilityElement(children: .contain)
    }

    private func rowButton(
        id: String,
        title: String,
        systemImage: String,
        accessibilityID: String,
        accessibilityLabel: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .frame(width: 16)
                Text(title)
                    .font(appearance.font(size: 12, weight: .bold))
                Spacer(minLength: 0)
            }
            .foregroundStyle(appearance.text)
            .padding(.vertical, 8)
            .padding(.horizontal, 6)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(accessibilityID)
        .accessibilityLabel(accessibilityLabel)
    }
}

enum BubbleMenus {
    static let primary: [BubbleMenuItem] = [
        BubbleMenuItem(id: "hermes", title: "HERMES", systemImage: "terminal", accessibilityID: "bubbleHermes", accessibilityLabel: "Hermes"),
        BubbleMenuItem(id: "voice", title: "VOICE", systemImage: "waveform", accessibilityID: "bubbleVoice", accessibilityLabel: "Voice assistant"),
        BubbleMenuItem(id: "projects", title: "PROJECTS", systemImage: "folder", accessibilityID: "bubbleProjects", accessibilityLabel: "Projects"),
        BubbleMenuItem(id: "system", title: "SYSTEM", systemImage: "server.rack", accessibilityID: "bubbleSystem", accessibilityLabel: "System"),
        BubbleMenuItem(id: "logs", title: "LOGS", systemImage: "list.bullet.rectangle", accessibilityID: "bubbleLogs", accessibilityLabel: "Logs"),
        BubbleMenuItem(id: "settings", title: "SETTINGS", systemImage: "slider.horizontal.3", accessibilityID: "bubbleSettings", accessibilityLabel: "Settings"),
    ]

    static func nested(_ id: String) -> [BubbleMenuItem] {
        switch id {
        case "hermes":
            return [
                item("hermes.open", "OPEN SHELL", "terminal", "bubbleHermesOpen", "Open Hermes shell"),
                item("hermes.status", "STATUS", "info.circle", "bubbleHermesStatus", "Hermes status"),
                item("hermes.interrupt", "INTERRUPT", "stop.circle", "bubbleHermesInterrupt", "Interrupt"),
                item("hermes.reconnect", "RECONNECT", "arrow.clockwise", "bubbleHermesReconnect", "Reconnect"),
                item("hermes.restart", "RESTART", "arrow.counterclockwise", "bubbleHermesRestart", "Restart"),
                item("hermes.logs", "LOGS", "list.bullet", "bubbleHermesLogs", "Hermes logs"),
            ]
        case "voice":
            return [
                item("voice.wake", "HEY SAMANTHA", "ear", "bubbleVoiceWake", "Hey Samantha"),
                item("voice.mute", "MUTE", "speaker.slash", "bubbleVoiceMute", "Mute"),
                item("voice.stop", "STOP SPEAKING", "stop.fill", "bubbleVoiceStop", "Stop speaking"),
                item("voice.route", "AUDIO ROUTE", "hifispeaker", "bubbleVoiceRoute", "Audio route"),
                item("voice.follow", "FOLLOW-UP", "clock", "bubbleVoiceFollow", "Follow-up"),
                item("voice.tts", "TTS STATUS", "waveform", "bubbleVoiceTTS", "TTS status"),
            ]
        case "system":
            return [
                item("system.gpus", "GPUS", "square.grid.2x2", "bubbleSystemGPUs", "GPUs"),
                item("system.models", "MODELS", "cpu", "bubbleSystemModels", "Models"),
                item("system.services", "SERVICES", "server.rack", "bubbleSystemServices", "Services"),
                item("system.storage", "STORAGE", "internaldrive", "bubbleSystemStorage", "Storage"),
                item("system.network", "NETWORK", "network", "bubbleSystemNetwork", "Network"),
            ]
        case "projects":
            return [
                item("projects.open", "ACTIVE PROJECT", "folder", "bubbleProjectsOpen", "Active project"),
                item("projects.builds", "BUILDS", "hammer", "bubbleProjectsBuilds", "Builds"),
                item("projects.git", "GIT", "arrow.triangle.branch", "bubbleProjectsGit", "Git"),
                item("projects.switch", "SWITCH PROJECT", "rectangle.2.swap", "bubbleProjectsSwitch", "Switch project"),
            ]
        case "logs":
            return [item("logs.open", "OPEN LOGS", "list.bullet", "bubbleLogsOpen", "Open logs")]
        case "settings":
            return [
                item("settings.open", "CONNECTION", "link", "bubbleSettingsOpen", "Connection settings"),
                item("settings.appearance", "APPEARANCE", "paintpalette", "bubbleSettingsAppearance", "Appearance"),
            ]
        default:
            return []
        }
    }

    private static func item(_ id: String, _ title: String, _ symbol: String, _ access: String, _ label: String) -> BubbleMenuItem {
        BubbleMenuItem(id: id, title: title, systemImage: symbol, accessibilityID: access, accessibilityLabel: label)
    }
}
