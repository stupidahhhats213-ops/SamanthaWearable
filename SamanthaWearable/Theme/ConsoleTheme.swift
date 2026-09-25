// Theme/ConsoleTheme.swift
import SwiftUI
import UIKit

enum ConsoleTone {
    case text, muted, accent, success, warning, error
}

enum ThemePreset: String, CaseIterable, Identifiable {
    case amber = "SAMANTHA AMBER"
    case vsDark = "VS DARK"
    case vsLight = "VS LIGHT"
    case terminal = "TERMINAL GREEN"
    case midnight = "MIDNIGHT BLUE"
    case contrast = "HIGH CONTRAST"
    case custom = "CUSTOM"
    var id: String { rawValue }
}

enum ConsoleDensity: String, CaseIterable, Identifiable {
    case compact = "COMPACT"
    case normal = "NORMAL"
    case relaxed = "RELAXED"
    var id: String { rawValue }
}

enum ConsoleFontChoice: String, CaseIterable, Identifiable {
    case system = "SYSTEM"
    case mono = "MONOSPACED"
    case monoSerif = "MONOSPACED SERIF"
    case developer = "DEVELOPER"
    var id: String { rawValue }
}

enum ConsoleCorners: String, CaseIterable, Identifiable {
    case square = "SQUARE"
    case subtle = "SUBTLE"
    case rounded = "ROUNDED"
    var id: String { rawValue }
    var radius: Double {
        switch self {
        case .square: return 0
        case .subtle: return 4
        case .rounded: return 10
        }
    }
}

enum ConsoleMotion: String, CaseIterable, Identifiable {
    case full = "FULL"
    case reduced = "REDUCED"
    case off = "OFF"
    var id: String { rawValue }
}

struct ThemePalette {
    var background: Color
    var panel: Color
    var panel2: Color
    var text: Color
    var muted: Color
    var accent: Color
    var border: Color
    var success: Color
    var warning: Color
    var error: Color
}

enum ThemePresets {
    static let amber = ThemePalette(
        background: Color(hex: "090806"),
        panel: Color(hex: "100D09"),
        panel2: Color(hex: "171109"),
        text: Color(hex: "EEE5D5"),
        muted: Color(hex: "817564"),
        accent: Color(hex: "F28A16"),
        border: Color(hex: "3D2A17"),
        success: Color(hex: "7DCEA0"),
        warning: Color(hex: "F2A11C"),
        error: Color(hex: "E45B32")
    )
    static let vsDark = ThemePalette(
        background: Color(hex: "1C1F24"),
        panel: Color(hex: "252A31"),
        panel2: Color(hex: "2C333C"),
        text: Color(hex: "D7DCE2"),
        muted: Color(hex: "8B949E"),
        accent: Color(hex: "4C8DFF"),
        border: Color(hex: "3A414B"),
        success: Color(hex: "3FB950"),
        warning: Color(hex: "D29922"),
        error: Color(hex: "F85149")
    )
    static let vsLight = ThemePalette(
        background: Color(hex: "F4F5F7"),
        panel: Color(hex: "FFFFFF"),
        panel2: Color(hex: "E8ECF1"),
        text: Color(hex: "1A1D23"),
        muted: Color(hex: "5C6570"),
        accent: Color(hex: "0E5FD8"),
        border: Color(hex: "C5CCD6"),
        success: Color(hex: "1A7F37"),
        warning: Color(hex: "9A6700"),
        error: Color(hex: "CF222E")
    )
    static let terminal = ThemePalette(
        background: Color(hex: "0A0F0A"),
        panel: Color(hex: "101610"),
        panel2: Color(hex: "162016"),
        text: Color(hex: "C8F5D0"),
        muted: Color(hex: "6B8F74"),
        accent: Color(hex: "3DDC84"),
        border: Color(hex: "1E3A28"),
        success: Color(hex: "3DDC84"),
        warning: Color(hex: "D6C15A"),
        error: Color(hex: "FF5C5C")
    )
    static let midnight = ThemePalette(
        background: Color(hex: "0B1220"),
        panel: Color(hex: "121A2B"),
        panel2: Color(hex: "182438"),
        text: Color(hex: "D5E4F2"),
        muted: Color(hex: "7E93A8"),
        accent: Color(hex: "5ED0E8"),
        border: Color(hex: "24344A"),
        success: Color(hex: "5ED6A0"),
        warning: Color(hex: "E0B15A"),
        error: Color(hex: "F07178")
    )
    static let contrast = ThemePalette(
        background: Color(hex: "000000"),
        panel: Color(hex: "000000"),
        panel2: Color(hex: "141414"),
        text: Color(hex: "FFFFFF"),
        muted: Color(hex: "D0D0D0"),
        accent: Color(hex: "FFE600"),
        border: Color(hex: "FFFFFF"),
        success: Color(hex: "00FF66"),
        warning: Color(hex: "FFCC00"),
        error: Color(hex: "FF3355")
    )

    static func palette(_ preset: ThemePreset) -> ThemePalette {
        switch preset {
        case .amber: return amber
        case .vsDark: return vsDark
        case .vsLight: return vsLight
        case .terminal: return terminal
        case .midnight: return midnight
        case .contrast: return contrast
        case .custom: return amber
        }
    }
}

@MainActor
final class AppearanceStore: ObservableObject {
    @Published var presetRaw: String
    @Published var densityRaw: String
    @Published var fontRaw: String
    @Published var cornersRaw: String
    @Published var motionRaw: String
    @Published var fontScale: Double
    @Published var borderWidth: Double
    @Published var cornerRadius: Double
    @Published var bubbleEnabled: Bool
    @Published var bubbleNX: Double
    @Published var bubbleNY: Double
    @Published var bubbleEdgeRaw: String
    @Published var bubbleNormalizedY: Double
    @Published var bubbleSize: Double
    @Published var bubbleOpacity: Double
    @Published var bubbleGlow: Double
    @Published var snapStrength: Double
    @Published var blurStrength: Double
    @Published var collapsedCSV: String
    @Published var lastPage: String
    @Published var logFilter: String
    @Published var selectedProject: String
    @Published var accentHex: String
    @Published var backgroundHex: String
    @Published var panelHex: String
    @Published var textHex: String
    @Published var borderHex: String
    @Published var successHex: String
    @Published var warningHex: String
    @Published var errorHex: String

    private let defaults = UserDefaults.standard

    init() {
        let store = UserDefaults.standard
        if store.object(forKey: "samantha.collapsed") == nil {
            store.set("project,network,build,alerts", forKey: "samantha.collapsed")
        }
        presetRaw = store.string(forKey: "samantha.theme") ?? ThemePreset.amber.rawValue
        densityRaw = store.string(forKey: "samantha.density") ?? ConsoleDensity.compact.rawValue
        fontRaw = store.string(forKey: "samantha.font") ?? ConsoleFontChoice.developer.rawValue
        cornersRaw = store.string(forKey: "samantha.corners") ?? ConsoleCorners.subtle.rawValue
        motionRaw = store.string(forKey: "samantha.motion") ?? ConsoleMotion.full.rawValue
        fontScale = store.object(forKey: "samantha.fontScale") as? Double ?? 1
        borderWidth = store.object(forKey: "samantha.borderWidth") as? Double ?? 1
        cornerRadius = store.object(forKey: "samantha.cornerRadius") as? Double ?? ConsoleCorners.subtle.radius
        bubbleEnabled = store.object(forKey: "samantha.bubble.enabled") as? Bool ?? true
        bubbleNX = store.object(forKey: "samantha.bubble.nx") as? Double ?? 0.9
        bubbleNY = store.object(forKey: "samantha.bubble.ny") as? Double ?? 0.55
        let restored = BubblePosition.restored(
            edgeRaw: store.string(forKey: "samantha.bubble.edge"),
            normalizedY: store.object(forKey: "samantha.bubble.nyNorm") as? Double,
            legacyX: store.object(forKey: "samantha.bubble.nx") as? Double,
            legacyY: store.object(forKey: "samantha.bubble.ny") as? Double
        )
        bubbleEdgeRaw = restored.edge.rawValue
        bubbleNormalizedY = restored.normalizedY
        bubbleSize = store.object(forKey: "samantha.bubble.size") as? Double ?? 52
        bubbleOpacity = store.object(forKey: "samantha.bubble.opacity") as? Double ?? 0.94
        bubbleGlow = store.object(forKey: "samantha.bubble.glow") as? Double ?? 0.35
        snapStrength = store.object(forKey: "samantha.bubble.snap") as? Double ?? 1
        blurStrength = store.object(forKey: "samantha.bubble.blur") as? Double ?? 0.85
        collapsedCSV = store.string(forKey: "samantha.collapsed") ?? "project,network,build,alerts"
        lastPage = store.string(forKey: "samantha.lastPage") ?? "home"
        logFilter = store.string(forKey: "samantha.logFilter") ?? "ALL"
        selectedProject = store.string(forKey: "samantha.project") ?? ""
        accentHex = store.string(forKey: "samantha.custom.accent") ?? "F28A16"
        backgroundHex = store.string(forKey: "samantha.custom.background") ?? "090806"
        panelHex = store.string(forKey: "samantha.custom.panel") ?? "100D09"
        textHex = store.string(forKey: "samantha.custom.text") ?? "EEE5D5"
        borderHex = store.string(forKey: "samantha.custom.border") ?? "3D2A17"
        successHex = store.string(forKey: "samantha.custom.success") ?? "7DCEA0"
        warningHex = store.string(forKey: "samantha.custom.warning") ?? "F2A11C"
        errorHex = store.string(forKey: "samantha.custom.error") ?? "E45B32"
    }

    var preset: ThemePreset {
        get { ThemePreset(rawValue: presetRaw) ?? .amber }
        set { set(\.presetRaw, newValue.rawValue, key: "samantha.theme") }
    }
    var density: ConsoleDensity {
        get { ConsoleDensity(rawValue: densityRaw) ?? .compact }
        set { set(\.densityRaw, newValue.rawValue, key: "samantha.density") }
    }
    var fontChoice: ConsoleFontChoice {
        get { ConsoleFontChoice(rawValue: fontRaw) ?? .developer }
        set { set(\.fontRaw, newValue.rawValue, key: "samantha.font") }
    }
    var corners: ConsoleCorners {
        get { ConsoleCorners(rawValue: cornersRaw) ?? .subtle }
        set {
            set(\.cornersRaw, newValue.rawValue, key: "samantha.corners")
            set(\.cornerRadius, newValue.radius, key: "samantha.cornerRadius")
        }
    }
    var motion: ConsoleMotion {
        get { ConsoleMotion(rawValue: motionRaw) ?? .full }
        set { set(\.motionRaw, newValue.rawValue, key: "samantha.motion") }
    }

    var prefersLight: Bool { preset == .vsLight }
    var radius: CGFloat { CGFloat(cornerRadius) }
    var lineWidth: CGFloat { CGFloat(max(1, borderWidth)) }

    var pad: CGFloat {
        let base: CGFloat
        switch density {
        case .compact: base = 8
        case .normal: base = 12
        case .relaxed: base = 16
        }
        return base
    }
    var rowGap: CGFloat {
        switch density {
        case .compact: return 2
        case .normal: return 5
        case .relaxed: return 8
        }
    }
    var sectionGap: CGFloat {
        switch density {
        case .compact: return 8
        case .normal: return 12
        case .relaxed: return 16
        }
    }

    func font(size: CGFloat, weight: Font.Weight = .medium) -> Font {
        let scaled = size * CGFloat(fontScale) * densityScale
        switch fontChoice {
        case .system:
            return .system(size: scaled, weight: weight)
        case .mono, .developer:
            return .system(size: scaled, weight: weight, design: .monospaced)
        case .monoSerif:
            return .system(size: scaled, weight: weight, design: .serif)
        }
    }

    private var densityScale: CGFloat {
        switch density {
        case .compact: return 0.96
        case .normal: return 1
        case .relaxed: return 1.08
        }
    }

    var motionAmount: Double {
        if UIAccessibility.isReduceMotionEnabled || motion == .off { return 0 }
        if motion == .reduced { return 0.35 }
        return 1
    }

    var palette: ThemePalette {
        if preset == .custom {
            return ThemePalette(
                background: Color(hex: backgroundHex),
                panel: Color(hex: panelHex),
                panel2: Color(hex: panelHex).opacity(0.86),
                text: Color(hex: textHex),
                muted: Color(hex: textHex).opacity(0.62),
                accent: Color(hex: accentHex),
                border: Color(hex: borderHex),
                success: Color(hex: successHex),
                warning: Color(hex: warningHex),
                error: Color(hex: errorHex)
            )
        }
        return ThemePresets.palette(preset)
    }

    var background: Color { palette.background }
    var panel: Color { palette.panel }
    var panel2: Color { palette.panel2 }
    var text: Color { palette.text }
    var muted: Color { palette.muted }
    var accent: Color { palette.accent }
    var border: Color { palette.border }
    var success: Color { palette.success }
    var warning: Color { palette.warning }
    var error: Color { palette.error }

    func color(_ tone: ConsoleTone) -> Color {
        switch tone {
        case .text: return text
        case .muted: return muted
        case .accent: return accent
        case .success: return success
        case .warning: return warning
        case .error: return error
        }
    }

    func tone(for status: String) -> ConsoleTone {
        let s = status.uppercased()
        if s.contains("FAIL") || s.contains("ERROR") || s.contains("OFFLINE") || s.contains("DOWN") || s.contains("CRITICAL") || s == "STOPPED" {
            return .error
        }
        if s.contains("WARN") || s.contains("DEGRADED") || s.contains("DIRTY") || s.contains("CONNECTING") {
            return .warning
        }
        if s.contains("UNKNOWN") || s.contains("NOT STARTED") || s.contains("INACTIVE") || s == "—" || s.isEmpty {
            return .muted
        }
        if s.contains("ACTIVE") || s.contains("RUNNING") || s.contains("ONLINE") || s.contains("PASS")
            || s.contains("HEALTHY") || s.contains("NOMINAL") || s.contains("CONNECTED") || s.contains("SUCCESS")
            || s.contains("UP") || s.contains("CLEAN") || s.contains("READY") || s.contains("LISTENING") {
            return .success
        }
        return .text
    }

    func isCollapsed(_ id: String) -> Bool {
        guard !id.isEmpty else { return false }
        return Set(collapsedCSV.split(separator: ",").map(String.init)).contains(id)
    }

    func toggleSection(_ id: String) {
        var flags = Set(collapsedCSV.split(separator: ",").map(String.init))
        if flags.contains(id) { flags.remove(id) } else { flags.insert(id) }
        set(\.collapsedCSV, flags.sorted().joined(separator: ","), key: "samantha.collapsed")
    }

    func resetBubble() {
        set(\.bubbleEdgeRaw, BubblePosition.default.edge.rawValue, key: "samantha.bubble.edge")
        set(\.bubbleNormalizedY, BubblePosition.default.normalizedY, key: "samantha.bubble.nyNorm")
    }

    func setBubbleEdge(_ value: String) { set(\.bubbleEdgeRaw, value, key: "samantha.bubble.edge") }
    func setBubbleNormalizedY(_ value: Double) { set(\.bubbleNormalizedY, value, key: "samantha.bubble.nyNorm") }

    var bubbleEdge: BubbleEdge { BubbleEdge(rawValue: bubbleEdgeRaw) ?? .right }

    func setFontScale(_ value: Double) { set(\.fontScale, value, key: "samantha.fontScale") }
    func setBorderWidth(_ value: Double) { set(\.borderWidth, value, key: "samantha.borderWidth") }
    func setCornerRadius(_ value: Double) { set(\.cornerRadius, value, key: "samantha.cornerRadius") }
    func setBubbleEnabled(_ value: Bool) { set(\.bubbleEnabled, value, key: "samantha.bubble.enabled") }
    func setBubbleSize(_ value: Double) { set(\.bubbleSize, value, key: "samantha.bubble.size") }
    func setBubbleOpacity(_ value: Double) { set(\.bubbleOpacity, value, key: "samantha.bubble.opacity") }
    func setBubbleGlow(_ value: Double) { set(\.bubbleGlow, value, key: "samantha.bubble.glow") }
    func setSnapStrength(_ value: Double) { set(\.snapStrength, value, key: "samantha.bubble.snap") }
    func setBlurStrength(_ value: Double) { set(\.blurStrength, value, key: "samantha.bubble.blur") }
    func setLastPage(_ value: String) { set(\.lastPage, value, key: "samantha.lastPage") }
    func setLogFilter(_ value: String) { set(\.logFilter, value, key: "samantha.logFilter") }
    func setSelectedProject(_ value: String) { set(\.selectedProject, value, key: "samantha.project") }
    func setAccentHex(_ value: String) { set(\.accentHex, value, key: "samantha.custom.accent") }
    func setBackgroundHex(_ value: String) { set(\.backgroundHex, value, key: "samantha.custom.background") }
    func setPanelHex(_ value: String) { set(\.panelHex, value, key: "samantha.custom.panel") }
    func setTextHex(_ value: String) { set(\.textHex, value, key: "samantha.custom.text") }
    func setBorderHex(_ value: String) { set(\.borderHex, value, key: "samantha.custom.border") }
    func setSuccessHex(_ value: String) { set(\.successHex, value, key: "samantha.custom.success") }
    func setWarningHex(_ value: String) { set(\.warningHex, value, key: "samantha.custom.warning") }
    func setErrorHex(_ value: String) { set(\.errorHex, value, key: "samantha.custom.error") }

    private func set<T>(_ keyPath: ReferenceWritableKeyPath<AppearanceStore, T>, _ value: T, key: String) {
        self[keyPath: keyPath] = value
        defaults.set(value as Any, forKey: key)
    }
}

extension Color {
    init(hex: String) {
        var raw = hex.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "#", with: "")
        if raw.count == 3 {
            raw = raw.map { "\($0)\($0)" }.joined()
        }
        var value: UInt64 = 0
        Scanner(string: raw).scanHexInt64(&value)
        let r = Double((value >> 16) & 0xFF) / 255
        let g = Double((value >> 8) & 0xFF) / 255
        let b = Double(value & 0xFF) / 255
        self.init(red: r, green: g, blue: b)
    }
}

func consoleHex(from color: Color) -> String? {
    let ui = UIColor(color)
    var r: CGFloat = 0
    var g: CGFloat = 0
    var b: CGFloat = 0
    var a: CGFloat = 0
    guard ui.getRed(&r, green: &g, blue: &b, alpha: &a) else { return nil }
    return String(format: "%02X%02X%02X", Int(r * 255), Int(g * 255), Int(b * 255))
}

struct GPUReading: Identifiable, Equatable {
    var id: Int
    var temp: Double
    var power: Double
    var vramUsed: Double
    var vramTotal: Double
    var util: Double
}

struct ConsoleSnapshot: Equatable {
    var ready = false
    var host = ""
    var gpus: [GPUReading] = []
    var hermesState = ""
    var hermesDetail = ""
    var hermesPID: Int?
    var mainName = ""
    var mainUnit = ""
    var mainUp: Bool?
    var helperName = ""
    var helperUnit = ""
    var helperUp: Bool?
    var voiceUp: Bool?
    var sttUnit = ""
    var sttUp: Bool?
    var buildName = ""
    var buildConclusion = ""
    var ageSec: Double?
}

struct ProjectRecord: Identifiable, Equatable {
    var id: String
    var name: String
    var branch: String
    var gitStatus: String
    var dirtyCount: Int
    var lastCommit: String
    var buildConclusion: String
    var buildName: String
    var exists: Bool
}

struct ConsoleEvent: Identifiable, Equatable {
    let id = UUID()
    let at: Date
    let channel: String
    let message: String
}

enum ConsoleRoute: Hashable {
    case hermes
    case voice
    case projects
    case system
    case models
    case gpus
    case logs
    case settings
    case appearance
    case wearable
    case project(String)

    var storage: String {
        switch self {
        case .hermes: return "hermes"
        case .voice: return "voice"
        case .projects: return "projects"
        case .system: return "system"
        case .models: return "models"
        case .gpus: return "gpus"
        case .logs: return "logs"
        case .settings: return "settings"
        case .appearance: return "appearance"
        case .wearable: return "wearable"
        case .project(let id): return "project:\(id)"
        }
    }

    init?(storage: String) {
        if storage.hasPrefix("project:") {
            self = .project(String(storage.dropFirst("project:".count)))
            return
        }
        switch storage {
        case "hermes": self = .hermes
        case "voice": self = .voice
        case "projects": self = .projects
        case "system": self = .system
        case "models": self = .models
        case "gpus": self = .gpus
        case "logs": self = .logs
        case "settings": self = .settings
        case "appearance": self = .appearance
        case "wearable": self = .wearable
        default: return nil
        }
    }
}
