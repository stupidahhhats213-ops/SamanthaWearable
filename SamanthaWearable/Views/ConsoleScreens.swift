// Views/ConsoleScreens.swift
import SwiftUI

struct HomeScreen: View {
    @ObservedObject var viewModel: DashboardViewModel
    @EnvironmentObject private var appearance: AppearanceStore
    var open: (ConsoleRoute) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: appearance.sectionGap) {
                Text("SAMANTHA NODE")
                    .font(appearance.font(size: 13, weight: .bold))
                    .foregroundStyle(appearance.accent)
                node
                runtime
                gpus
                events
                project
                wearable
                network
                build
                if let err = viewModel.lastError ?? viewModel.heartbeat.lastError ?? viewModel.metaGlasses.lastError {
                    Text(err)
                        .font(appearance.font(size: 11, weight: .medium))
                        .foregroundStyle(appearance.error)
                }
            }
            .padding(appearance.pad)
            .padding(.bottom, 72)
            .accessibilityIdentifier("homeScroll")
        }
        .accessibilityIdentifier("homeScroll")
        .background(appearance.background)
        .toolbar(.hidden, for: .navigationBar)
        .safeAreaInset(edge: .bottom) {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("COMMAND TARGET")
                        .font(appearance.font(size: 10, weight: .bold))
                        .foregroundStyle(appearance.muted)
                    Spacer()
                    FilterChip(title: "SAMANTHA", selected: viewModel.commandTarget == "SAMANTHA") {
                        viewModel.commandTarget = "SAMANTHA"
                    }
                    FilterChip(title: "HERMES", selected: viewModel.commandTarget == "HERMES") {
                        viewModel.commandTarget = "HERMES"
                    }
                }
                CommandField(text: $viewModel.commandDraft, target: viewModel.commandTarget) {
                    let raw = viewModel.commandDraft
                    viewModel.commandDraft = ""
                    if raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "home" {
                        return
                    }
                    if let route = viewModel.route(forShortcut: raw) {
                        open(route)
                    } else {
                        viewModel.submitConsole(raw)
                    }
                }
            }
            .padding(.horizontal, appearance.pad)
            .padding(.bottom, 6)
            .background(appearance.background.opacity(0.94))
        }
    }

    private var node: some View {
        let link = viewModel.metaGlasses.connectedDeviceName ?? (viewModel.metaGlasses.glassesConnected ? "LINKED" : "DISCONNECTED")
        let state = viewModel.nodeState
        return TerminalPanel(title: "SAMANTHA NODE", trailing: state) {
            MetricRow(label: "Host", value: viewModel.console.host.isEmpty ? "—" : viewModel.console.host)
            MetricRow(label: "State", value: state)
            MetricRow(label: "Link", value: link)
            MetricRow(label: "Path", value: viewModel.hostLabel, tone: .muted)
        }
    }

    private var runtime: some View {
        let snap = viewModel.console
        let voice = viewModel.voice
        return TerminalPanel(title: "RUNTIME", sectionID: "runtime") {
            MetricRow(
                label: "80B",
                value: serviceLine(up: snap.mainUp, unit: snap.mainUnit, extra: ms(voice.llmFirstTokenMs, suffix: "TTFT"))
            )
            MetricRow(
                label: "F5",
                value: serviceLine(up: snap.voiceUp, unit: snap.voiceUp == true ? "ACTIVE" : nil, extra: ms(voice.f5FirstChunkMs ?? voice.synthesisMs, suffix: "TTS"))
            )
            MetricRow(label: "Hermes", value: snap.hermesState.isEmpty ? "—" : snap.hermesState)
            MetricRow(label: "STT", value: sttLine)
        }
    }

    private var gpus: some View {
        TerminalPanel(title: "GPU ARRAY", trailing: viewModel.console.ready ? "\(viewModel.console.gpus.count)" : "WAIT", sectionID: "gpus") {
            if !viewModel.console.ready {
                MetricRow(label: "Feed", value: "WAITING", tone: .muted)
            } else if viewModel.console.gpus.isEmpty {
                MetricRow(label: "Feed", value: "NO GPU ROWS", tone: .warning)
            } else {
                ForEach(viewModel.console.gpus) { gpu in
                    GPUBar(gpu: gpu)
                }
            }
            ConsoleButton(title: "OPEN GPUS") { open(.gpus) }
        }
    }

    private var events: some View {
        TerminalPanel(title: "EVENTS", trailing: "\(viewModel.events.count)", sectionID: "events") {
            if viewModel.events.isEmpty {
                MetricRow(label: "Log", value: "NO EVENTS YET", tone: .muted)
            } else {
                ForEach(viewModel.events.suffix(6).reversed()) { event in
                    EventLine(event: event)
                }
            }
            ConsoleButton(title: "OPEN LOGS") { open(.logs) }
        }
    }

    private var project: some View {
        let current = viewModel.projects.first { $0.id == appearance.selectedProject } ?? viewModel.projects.first
        return TerminalPanel(title: "PROJECT", trailing: current?.name, sectionID: "project") {
            if let current {
                MetricRow(label: "Name", value: current.name)
                MetricRow(label: "Branch", value: current.branch.isEmpty ? "—" : current.branch)
                MetricRow(label: "Tree", value: current.dirtyCount > 0 ? "\(current.dirtyCount) MODIFIED" : "CLEAN")
                MetricRow(label: "Build", value: current.buildConclusion.isEmpty ? "—" : current.buildConclusion.uppercased())
                MetricRow(label: "Commit", value: current.lastCommit.isEmpty ? "—" : current.lastCommit, tone: .muted)
            } else {
                MetricRow(label: "Feed", value: "NO PROJECT LIST", tone: .muted)
            }
            ConsoleButton(title: "OPEN PROJECTS") { open(.projects) }
        }
    }

    private var wearable: some View {
        let meta = viewModel.metaGlasses
        return TerminalPanel(title: "WEARABLE", trailing: meta.connectionState.rawValue, sectionID: "wearable") {
            MetricRow(label: "Device", value: meta.connectedDeviceName ?? "—")
            MetricRow(label: "Session", value: meta.sessionStateText)
            MetricRow(label: "Battery", value: viewModel.glassesBatteryText)
            MetricRow(label: "Route", value: viewModel.voice.audioRoute)
            ConsoleButton(title: viewModel.glassesActionBusy ? "WORKING" : "CONNECT", prominent: true) {
                viewModel.connectMetaGlasses()
            }
            .disabled(viewModel.glassesActionBusy || meta.connectionState == .connected || meta.connectionState == .connecting)
            ConsoleButton(title: "GLASSES PAGE") { open(.wearable) }
        }
    }

    private var network: some View {
        TerminalPanel(title: "NETWORK", sectionID: "network") {
            MetricRow(label: "Phone", value: viewModel.networkText)
            MetricRow(label: "Battery", value: viewModel.batteryText)
            MetricRow(label: "Latency", value: viewModel.latencyMs.map { String(format: "%.0f ms", $0) } ?? "—")
            MetricRow(label: "Host", value: viewModel.serverURL.replacingOccurrences(of: "http://", with: ""), tone: .muted)
        }
    }

    private var build: some View {
        TerminalPanel(title: "BUILD", sectionID: "build") {
            MetricRow(label: "App", value: "\(AppConfig.appVersion) (\(AppConfig.buildNumber))")
            MetricRow(label: "CI", value: viewModel.console.buildConclusion.isEmpty ? "—" : viewModel.console.buildConclusion.uppercased())
            MetricRow(label: "Name", value: viewModel.console.buildName.isEmpty ? "—" : viewModel.console.buildName, tone: .muted)
        }
    }

    private var sttLine: String {
        if viewModel.console.sttUp == true { return "ACTIVE" }
        if viewModel.console.sttUnit.isEmpty { return "—" }
        if viewModel.console.sttUnit == "inactive" || viewModel.console.sttUnit == "not started" { return "NOT STARTED" }
        return viewModel.console.sttUnit.uppercased()
    }

    private func serviceLine(up: Bool?, unit: String?, extra: String) -> String {
        let state: String
        if up == true || unit == "active" || unit == "ACTIVE" {
            state = "ACTIVE"
        } else if up == false {
            state = "OFFLINE"
        } else if let unit, !unit.isEmpty {
            state = unit.uppercased()
        } else {
            state = "—"
        }
        return extra.isEmpty ? state : "\(state)  \(extra)"
    }

    private func ms(_ value: Double?, suffix: String) -> String {
        guard let value else { return "" }
        return String(format: "%.2fs %@", value / 1000, suffix)
    }
}

struct HermesScreen: View {
    @ObservedObject var viewModel: DashboardViewModel
    @EnvironmentObject private var appearance: AppearanceStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: appearance.sectionGap) {
                TerminalPanel(title: "HERMES // INTERACTIVE", trailing: viewModel.console.hermesState) {
                    MetricRow(label: "Status", value: viewModel.console.hermesState.isEmpty ? "—" : viewModel.console.hermesState)
                    MetricRow(label: "PID", value: viewModel.console.hermesPID.map(String.init) ?? "—")
                    MetricRow(label: "Task", value: viewModel.console.hermesDetail.isEmpty ? "—" : viewModel.console.hermesDetail, tone: .muted)
                }
                TerminalPanel(title: "SHELL") {
                    if viewModel.terminal.isEmpty {
                        Text("No commands yet. This sends through the wearable command path, not a raw shell.")
                            .font(appearance.font(size: 11, weight: .regular))
                            .foregroundStyle(appearance.muted)
                    }
                    ForEach(Array(viewModel.terminal.suffix(40).enumerated()), id: \.offset) { _, line in
                        Text(line)
                            .font(appearance.font(size: 12, weight: .regular))
                            .foregroundStyle(line.hasPrefix(">") ? appearance.accent : appearance.text)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    CommandField(text: $viewModel.commandDraft, target: "HERMES") {
                        let raw = viewModel.commandDraft
                        viewModel.commandDraft = ""
                        viewModel.commandTarget = "HERMES"
                        viewModel.submitConsole(raw)
                    }
                }
                HStack(spacing: 8) {
                    ConsoleButton(title: "^C INTERRUPT") { viewModel.interruptHermes() }
                    ConsoleButton(title: "R RECONNECT") { viewModel.reconnectEvents() }
                }
                ConsoleButton(title: "STATUS", prominent: true) {
                    viewModel.commandTarget = "HERMES"
                    viewModel.submitConsole("status")
                }
            }
            .padding(appearance.pad)
            .padding(.bottom, 88)
        }
        .background(appearance.background)
        .navigationTitle("HERMES")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct VoiceScreen: View {
    @ObservedObject var viewModel: DashboardViewModel
    @EnvironmentObject private var appearance: AppearanceStore

    var body: some View {
        let voice = viewModel.voice
        ScrollView {
            VStack(alignment: .leading, spacing: appearance.sectionGap) {
                TerminalPanel(title: "VOICE ASSISTANT", trailing: voice.phase.rawValue) {
                    MetricRow(label: "Status", value: voice.phase.rawValue)
                    MetricRow(label: "Wake", value: "HEY SAMANTHA")
                    MetricRow(label: "Route", value: voice.audioRoute)
                    MetricRow(label: "Detail", value: voice.routeDetail.isEmpty ? "—" : voice.routeDetail, tone: .muted)
                    MetricRow(label: "TTS", value: voice.voiceEngine == "F5-TTS" ? "F5 ONLINE" : voice.voiceEngine)
                    MetricRow(label: "Follow", value: voice.followUpOpen ? String(format: "OPEN %.0fs", voice.followUpRemaining) : "CLOSED")
                    MetricRow(label: "Heard", value: voice.transcript.isEmpty ? "—" : voice.transcript)
                    MetricRow(label: "Reply", value: voice.reply.isEmpty ? "—" : voice.reply)
                }
                TerminalPanel(title: "LATENCY") {
                    MetricRow(label: "Token", value: ms(voice.llmFirstTokenMs))
                    MetricRow(label: "Sentence", value: ms(voice.firstSentenceMs))
                    MetricRow(label: "Audio", value: ms(voice.f5FirstChunkMs ?? voice.playbackStartMs))
                    MetricRow(label: "API", value: ms(voice.apiLatencyMs))
                }
                Toggle("Wake phrase", isOn: Binding(
                    get: { voice.heySamanthaEnabled },
                    set: { voice.heySamanthaEnabled = $0; viewModel.syncVoice() }
                ))
                .font(appearance.font(size: 12, weight: .bold))
                .tint(appearance.accent)
                Toggle("Mute", isOn: Binding(get: { voice.muted }, set: { voice.muted = $0 }))
                    .font(appearance.font(size: 12, weight: .bold))
                    .tint(appearance.accent)
                Toggle("Proactive updates", isOn: Binding(get: { voice.proactiveEnabled }, set: { voice.proactiveEnabled = $0 }))
                    .font(appearance.font(size: 12, weight: .bold))
                    .tint(appearance.accent)
                ConsoleButton(title: "TALK", prominent: true) { viewModel.voice.startTalking() }
                ConsoleButton(title: "STOP SPEAKING") { viewModel.voice.stopSpeaking() }
                if voice.needsConfirmation {
                    ConsoleButton(title: "CONFIRM", prominent: true) { viewModel.voice.confirmPending() }
                    ConsoleButton(title: "CANCEL") { viewModel.voice.cancelPending() }
                }
            }
            .padding(appearance.pad)
            .padding(.bottom, 88)
        }
        .background(appearance.background)
        .navigationTitle("VOICE")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func ms(_ value: Double?) -> String {
        guard let value else { return "—" }
        return String(format: "%.0f ms", value)
    }
}

struct ProjectsScreen: View {
    @ObservedObject var viewModel: DashboardViewModel
    @EnvironmentObject private var appearance: AppearanceStore
    var open: (ConsoleRoute) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: appearance.sectionGap) {
                if viewModel.projects.isEmpty {
                    TerminalPanel(title: "WORKSPACE") {
                        MetricRow(label: "Feed", value: "NO PROJECT LIST", tone: .muted)
                    }
                }
                ForEach(viewModel.projects) { project in
                    Button {
                        appearance.setSelectedProject(project.id)
                        open(.project(project.id))
                    } label: {
                        TerminalPanel(title: project.name, trailing: project.dirtyCount > 0 ? "DIRTY" : "CLEAN") {
                            MetricRow(label: "Branch", value: project.branch.isEmpty ? "—" : project.branch)
                            MetricRow(label: "Git", value: project.gitStatus.isEmpty ? "—" : project.gitStatus, tone: .muted)
                            MetricRow(label: "Build", value: project.buildConclusion.isEmpty ? "—" : project.buildConclusion.uppercased())
                            MetricRow(label: "Commit", value: project.lastCommit.isEmpty ? "—" : project.lastCommit, tone: .muted)
                        }
                    }
                    .buttonStyle(.plain)
                }
                ConsoleButton(title: "REFRESH") { viewModel.refreshProjects() }
            }
            .padding(appearance.pad)
            .padding(.bottom, 88)
        }
        .background(appearance.background)
        .navigationTitle("PROJECTS")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { viewModel.refreshProjects() }
    }
}

struct ProjectDetailScreen: View {
    @ObservedObject var viewModel: DashboardViewModel
    @EnvironmentObject private var appearance: AppearanceStore
    let projectID: String
    @State private var detail: ProjectRecord?

    var body: some View {
        let project = detail ?? viewModel.projects.first { $0.id == projectID }
        ScrollView {
            VStack(alignment: .leading, spacing: appearance.sectionGap) {
                TerminalPanel(title: project?.name ?? projectID, trailing: (project?.dirtyCount ?? 0) > 0 ? "DIRTY" : "CLEAN") {
                    MetricRow(label: "ID", value: projectID, tone: .muted)
                    MetricRow(label: "Branch", value: project?.branch ?? "—")
                    MetricRow(label: "Tree", value: tree(project))
                    MetricRow(label: "Git", value: project?.gitStatus ?? "—", tone: .muted)
                    MetricRow(label: "Commit", value: project?.lastCommit ?? "—")
                    MetricRow(label: "Build", value: (project?.buildConclusion ?? "").isEmpty ? "—" : project!.buildConclusion.uppercased())
                    MetricRow(label: "Run", value: project?.buildName ?? "—", tone: .muted)
                }
                if viewModel.console.hermesState == "RUNNING", projectID.contains("hermes") || (project?.name ?? "").lowercased().contains("hermes") {
                    TerminalPanel(title: "HERMES") {
                        MetricRow(label: "State", value: viewModel.console.hermesState)
                        MetricRow(label: "Task", value: viewModel.console.hermesDetail.isEmpty ? "—" : viewModel.console.hermesDetail, tone: .muted)
                    }
                }
            }
            .padding(appearance.pad)
            .padding(.bottom, 88)
        }
        .background(appearance.background)
        .navigationTitle("PROJECT")
        .navigationBarTitleDisplayMode(.inline)
        .task { detail = await viewModel.loadProject(projectID) }
    }

    private func tree(_ project: ProjectRecord?) -> String {
        guard let project else { return "—" }
        if !project.exists { return "MISSING" }
        return project.dirtyCount > 0 ? "\(project.dirtyCount) MODIFIED" : "CLEAN"
    }
}

struct SystemScreen: View {
    @ObservedObject var viewModel: DashboardViewModel
    @EnvironmentObject private var appearance: AppearanceStore
    var open: (ConsoleRoute) -> Void

    var body: some View {
        let snap = viewModel.console
        ScrollView {
            VStack(alignment: .leading, spacing: appearance.sectionGap) {
                TerminalPanel(title: "SERVICES") {
                    MetricRow(label: "Main", value: flag(snap.mainUp, snap.mainUnit))
                    MetricRow(label: "Voice", value: flag(snap.voiceUp, nil))
                    MetricRow(label: "Hermes", value: snap.hermesState.isEmpty ? "—" : snap.hermesState)
                    MetricRow(label: "STT", value: snap.sttUp == true ? "ACTIVE" : (snap.sttUnit.isEmpty ? "—" : snap.sttUnit.uppercased()))
                    MetricRow(label: "Helper", value: flag(snap.helperUp, snap.helperUnit))
                    MetricRow(label: "Listener", value: viewModel.connectionState.rawValue)
                }
                TerminalPanel(title: "NETWORK") {
                    MetricRow(label: "Phone", value: viewModel.networkText)
                    MetricRow(label: "Server", value: viewModel.serverURL.replacingOccurrences(of: "http://", with: ""), tone: .muted)
                    MetricRow(label: "Ping", value: viewModel.latencyMs.map { String(format: "%.0f ms", $0) } ?? "—")
                }
                TerminalPanel(title: "STORAGE") {
                    MetricRow(label: "Disk", value: "NOT REPORTED", tone: .muted)
                }
                ConsoleButton(title: "GPUS") { open(.gpus) }
                ConsoleButton(title: "MODELS") { open(.models) }
                ConsoleButton(title: "GLASSES") { open(.wearable) }
                ConsoleButton(title: "HEALTH CHECK", prominent: true) { viewModel.testConnection() }
                if let test = viewModel.testResult {
                    Text(test)
                        .font(appearance.font(size: 11, weight: .medium))
                        .foregroundStyle(appearance.text)
                }
            }
            .padding(appearance.pad)
            .padding(.bottom, 88)
        }
        .background(appearance.background)
        .navigationTitle("SYSTEM")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func flag(_ up: Bool?, _ unit: String?) -> String {
        if up == true { return "ACTIVE" }
        if up == false { return unit?.isEmpty == false ? unit!.uppercased() : "OFFLINE" }
        return "—"
    }
}

struct GPUScreen: View {
    @ObservedObject var viewModel: DashboardViewModel
    @EnvironmentObject private var appearance: AppearanceStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: appearance.sectionGap) {
                if viewModel.console.gpus.isEmpty {
                    TerminalPanel(title: "GPU ARRAY") {
                        MetricRow(label: "Feed", value: viewModel.console.ready ? "NO GPU ROWS" : "WAITING", tone: .muted)
                    }
                }
                ForEach(viewModel.console.gpus) { gpu in
                    TerminalPanel(title: "GPU \(gpu.id)", trailing: String(format: "%.0f%%", gpu.util)) {
                        GPUBar(gpu: gpu)
                        MetricRow(label: "Temp", value: String(format: "%.0f C", gpu.temp))
                        MetricRow(label: "Power", value: String(format: "%.0f W", gpu.power))
                        MetricRow(label: "VRAM", value: String(format: "%.1f / %.1f G", gpu.vramUsed / 1024, gpu.vramTotal / 1024))
                        MetricRow(label: "Util", value: String(format: "%.0f%%", gpu.util))
                        MetricRow(label: "PCIe", value: "—", tone: .muted)
                        MetricRow(label: "Role", value: "—", tone: .muted)
                    }
                }
            }
            .padding(appearance.pad)
            .padding(.bottom, 88)
        }
        .background(appearance.background)
        .navigationTitle("GPUS")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct ModelsScreen: View {
    @ObservedObject var viewModel: DashboardViewModel
    @EnvironmentObject private var appearance: AppearanceStore

    var body: some View {
        let snap = viewModel.console
        let voice = viewModel.voice
        ScrollView {
            VStack(alignment: .leading, spacing: appearance.sectionGap) {
                TerminalPanel(title: "MAIN MODEL", trailing: snap.mainUp == true ? "ACTIVE" : "OFFLINE") {
                    MetricRow(label: "Name", value: snap.mainName.isEmpty ? "—" : snap.mainName)
                    MetricRow(label: "Endpoint", value: "127.0.0.1:8010", tone: .muted)
                    MetricRow(label: "Health", value: snap.mainUp == true ? "ACTIVE" : (snap.mainUnit.isEmpty ? "—" : snap.mainUnit.uppercased()))
                    MetricRow(label: "TTFT", value: ms(voice.llmFirstTokenMs))
                    MetricRow(label: "TPS", value: "—", tone: .muted)
                    MetricRow(label: "Context", value: "—", tone: .muted)
                    MetricRow(label: "VRAM", value: "—", tone: .muted)
                }
                TerminalPanel(title: "HELPER", trailing: snap.helperUp == true ? "ACTIVE" : snap.helperUnit.uppercased()) {
                    MetricRow(label: "Name", value: snap.helperName.isEmpty ? "—" : snap.helperName)
                    MetricRow(label: "Endpoint", value: "127.0.0.1:8012", tone: .muted)
                    MetricRow(label: "Health", value: snap.helperUp == true ? "ACTIVE" : (snap.helperUnit.isEmpty ? "—" : snap.helperUnit.uppercased()))
                }
                TerminalPanel(title: "TTS", trailing: snap.voiceUp == true ? "F5" : "OFFLINE") {
                    MetricRow(label: "Engine", value: "F5")
                    MetricRow(label: "GPU", value: voice.ttsGPU)
                    MetricRow(label: "Latency", value: ms(voice.synthesisMs ?? voice.f5FirstChunkMs))
                }
                TerminalPanel(title: "STT") {
                    MetricRow(label: "Status", value: snap.sttUp == true ? "ACTIVE" : (snap.sttUnit.isEmpty ? "—" : snap.sttUnit.uppercased()))
                    MetricRow(label: "Device", value: "—", tone: .muted)
                }
            }
            .padding(appearance.pad)
            .padding(.bottom, 88)
        }
        .background(appearance.background)
        .navigationTitle("MODELS")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func ms(_ value: Double?) -> String {
        guard let value else { return "—" }
        return String(format: "%.0f ms", value)
    }
}

struct LogsScreen: View {
    @ObservedObject var viewModel: DashboardViewModel
    @EnvironmentObject private var appearance: AppearanceStore
    @State private var query = ""

    private let filters = ["ALL", "SYSTEM", "GPU", "HERMES", "VOICE", "BUILD", "WEARABLE"]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: appearance.sectionGap) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(filters, id: \.self) { filter in
                            FilterChip(title: filter, selected: appearance.logFilter == filter) {
                                appearance.setLogFilter(filter)
                            }
                        }
                    }
                }
                TextField("filter text", text: $query)
                    .font(appearance.font(size: 12, weight: .medium))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .padding(8)
                    .background(appearance.panel)
                    .overlay(
                        RoundedRectangle(cornerRadius: appearance.radius, style: .continuous)
                            .stroke(appearance.border, lineWidth: appearance.lineWidth)
                    )
                TerminalPanel(title: "EVENTS") {
                    let rows = filtered
                    if rows.isEmpty {
                        MetricRow(label: "Log", value: "NO MATCHING LINES", tone: .muted)
                    }
                    ForEach(rows.reversed()) { event in
                        EventLine(event: event)
                    }
                }
            }
            .padding(appearance.pad)
            .padding(.bottom, 88)
        }
        .background(appearance.background)
        .navigationTitle("LOGS")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var filtered: [ConsoleEvent] {
        viewModel.events.filter { event in
            let channelOK = appearance.logFilter == "ALL" || event.channel == appearance.logFilter
            let textOK = query.isEmpty
                || event.message.localizedCaseInsensitiveContains(query)
                || event.channel.localizedCaseInsensitiveContains(query)
            return channelOK && textOK
        }
    }
}

struct WearableScreen: View {
    @ObservedObject var viewModel: DashboardViewModel
    @EnvironmentObject private var appearance: AppearanceStore

    var body: some View {
        let meta = viewModel.metaGlasses
        ScrollView {
            VStack(alignment: .leading, spacing: appearance.sectionGap) {
                TerminalPanel(title: "META GLASSES", trailing: meta.connectionState.rawValue) {
                    MetricRow(label: "Status", value: meta.connectionState.rawValue)
                    MetricRow(label: "Register", value: meta.registrationState.rawValue)
                    MetricRow(label: "Session", value: meta.sessionStateText)
                    MetricRow(label: "Device", value: meta.connectedDeviceName ?? "—")
                    MetricRow(label: "Link", value: meta.linkStateText)
                    MetricRow(label: "Compat", value: meta.compatibilityText)
                    MetricRow(label: "Camera", value: meta.cameraLabel.rawValue)
                    MetricRow(label: "Mic", value: meta.microphoneLabel.rawValue)
                    MetricRow(label: "Audio", value: meta.audioOutputLabel.rawValue)
                    MetricRow(label: "Battery", value: viewModel.glassesBatteryText)
                }
                ConsoleButton(title: "CONNECT", prominent: true) { viewModel.connectMetaGlasses() }
                    .disabled(viewModel.glassesActionBusy || meta.connectionState == .connected || meta.connectionState == .connecting)
                ConsoleButton(title: "DISCONNECT") { viewModel.disconnectMetaGlasses() }
                    .disabled(viewModel.glassesActionBusy || !meta.glassesConnected)
                ConsoleButton(title: meta.isCapturingPhoto ? "CAPTURING" : "TEST CAMERA") { viewModel.testCamera() }
                    .disabled(viewModel.glassesActionBusy || !meta.glassesConnected || meta.isCapturingPhoto)
                if meta.requiresFirmwareUpdate {
                    ConsoleButton(title: "FIRMWARE UPDATE") { Task { await meta.openFirmwareUpdate() } }
                }
            }
            .padding(appearance.pad)
            .padding(.bottom, 88)
        }
        .background(appearance.background)
        .navigationTitle("GLASSES")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct AppearanceScreen: View {
    @EnvironmentObject private var appearance: AppearanceStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: appearance.sectionGap) {
                TerminalPanel(title: "THEME") {
                    ForEach(ThemePreset.allCases) { preset in
                        FilterChip(title: preset.rawValue, selected: appearance.preset == preset) {
                            appearance.preset = preset
                        }
                    }
                }
                TerminalPanel(title: "TYPE") {
                    pickerRow("DENSITY") {
                        ForEach(ConsoleDensity.allCases) { item in
                            FilterChip(title: item.rawValue, selected: appearance.density == item) { appearance.density = item }
                        }
                    }
                    pickerRow("FONT") {
                        ForEach(ConsoleFontChoice.allCases) { item in
                            FilterChip(title: item.rawValue, selected: appearance.fontChoice == item) { appearance.fontChoice = item }
                        }
                    }
                    pickerRow("CORNERS") {
                        ForEach(ConsoleCorners.allCases) { item in
                            FilterChip(title: item.rawValue, selected: appearance.corners == item) { appearance.corners = item }
                        }
                    }
                    pickerRow("MOTION") {
                        ForEach(ConsoleMotion.allCases) { item in
                            FilterChip(title: item.rawValue, selected: appearance.motion == item) { appearance.motion = item }
                        }
                    }
                    slider("FONT SIZE", value: appearance.fontScale, range: 0.85...1.25) { appearance.setFontScale($0) }
                    slider("BORDER", value: appearance.borderWidth, range: 1...3) { appearance.setBorderWidth($0) }
                    slider("RADIUS", value: appearance.cornerRadius, range: 0...16) { appearance.setCornerRadius($0) }
                }
                if appearance.preset == .custom {
                    TerminalPanel(title: "CUSTOM") {
                        colorRow("ACCENT", hex: appearance.accentHex) { appearance.setAccentHex($0) }
                        colorRow("BACKGROUND", hex: appearance.backgroundHex) { appearance.setBackgroundHex($0) }
                        colorRow("PANEL", hex: appearance.panelHex) { appearance.setPanelHex($0) }
                        colorRow("TEXT", hex: appearance.textHex) { appearance.setTextHex($0) }
                        colorRow("BORDER", hex: appearance.borderHex) { appearance.setBorderHex($0) }
                        colorRow("SUCCESS", hex: appearance.successHex) { appearance.setSuccessHex($0) }
                        colorRow("WARNING", hex: appearance.warningHex) { appearance.setWarningHex($0) }
                        colorRow("ERROR", hex: appearance.errorHex) { appearance.setErrorHex($0) }
                    }
                }
                TerminalPanel(title: "SAMANTHA BUBBLE") {
                    Toggle("Enabled", isOn: Binding(get: { appearance.bubbleEnabled }, set: { appearance.setBubbleEnabled($0) }))
                        .font(appearance.font(size: 12, weight: .bold))
                        .tint(appearance.accent)
                    slider("SIZE", value: appearance.bubbleSize, range: 40...72) { appearance.setBubbleSize($0) }
                    slider("OPACITY", value: appearance.bubbleOpacity, range: 0.4...1) { appearance.setBubbleOpacity($0) }
                    slider("GLOW", value: appearance.bubbleGlow, range: 0...1) { appearance.setBubbleGlow($0) }
                    slider("SNAP", value: appearance.snapStrength, range: 0.4...1) { appearance.setSnapStrength($0) }
                    slider("BLUR", value: appearance.blurStrength, range: 0...1) { appearance.setBlurStrength($0) }
                    pickerRow("ANIMATION") {
                        ForEach(ConsoleMotion.allCases) { item in
                            FilterChip(title: item.rawValue, selected: appearance.motion == item) { appearance.motion = item }
                        }
                    }
                    ConsoleButton(title: "RESET POSITION") { appearance.resetBubble() }
                        .accessibilityIdentifier("bubbleResetPosition")
                }
            }
            .padding(appearance.pad)
            .padding(.bottom, 88)
        }
        .background(appearance.background)
        .navigationTitle("APPEARANCE")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func pickerRow<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(appearance.font(size: 10, weight: .bold))
                .foregroundStyle(appearance.muted)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) { content() }
            }
        }
    }

    private func slider(_ title: String, value: Double, range: ClosedRange<Double>, set: @escaping (Double) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(title)  \(String(format: "%.2f", value))")
                .font(appearance.font(size: 10, weight: .bold))
                .foregroundStyle(appearance.muted)
            Slider(value: Binding(get: { value }, set: set), in: range)
                .tint(appearance.accent)
        }
    }

    private func colorRow(_ title: String, hex: String, set: @escaping (String) -> Void) -> some View {
        HStack {
            Text(title)
                .font(appearance.font(size: 11, weight: .bold))
                .foregroundStyle(appearance.muted)
            Spacer()
            ColorPicker("", selection: Binding(
                get: { Color(hex: hex) },
                set: { color in
                    if let next = consoleHex(from: color) { set(next) }
                }
            ), supportsOpacity: false)
            .labelsHidden()
        }
    }
}
