// ViewModels/DashboardViewModel.swift
import Foundation
import Combine
import SwiftUI

enum ConnectionState: String {
    case disconnected = "DISCONNECTED"
    case connecting = "CONNECTING"
    case connected = "CONNECTED"
    case error = "ERROR"
}

@MainActor
final class DashboardViewModel: ObservableObject {
    @Published var connectionState: ConnectionState = .disconnected
    @Published var lastError: String?
    @Published var latencyMs: Double?
    @Published var serverService: String?
    @Published var serverAPIVersion: String?
    @Published var registered = false
    @Published var lastHealthAt: Date?
    @Published var testResult: String?
    @Published var photoPreviewVisible = false
    @Published var glassesActionBusy = false
    @Published var console = ConsoleSnapshot()
    @Published var projects: [ProjectRecord] = []
    @Published var events: [ConsoleEvent] = []
    @Published var terminal: [String] = []
    @Published var commandTarget = "SAMANTHA"
    @Published var commandDraft = ""

    @Published var serverURL: String {
        didSet { UserDefaults.standard.set(serverURL, forKey: AppConfig.Keys.serverURL) }
    }
    @Published var authEnabled: Bool {
        didSet { UserDefaults.standard.set(authEnabled, forKey: AppConfig.Keys.authEnabled) }
    }
    @Published var apiToken: String = "" {
        didSet {
            if apiToken.isEmpty {
                KeychainStore.delete(account: AppConfig.Keys.apiTokenKeychain)
            } else {
                KeychainStore.set(apiToken, account: AppConfig.Keys.apiTokenKeychain)
            }
        }
    }
    @Published var heartbeatInterval: Double {
        didSet { UserDefaults.standard.set(heartbeatInterval, forKey: AppConfig.Keys.heartbeatInterval) }
    }

    let telemetry = DeviceTelemetry()
    let metaGlasses = MetaGlassesService()
    let voice = VoiceAssistantService()
    private let voiceSessionID = UserDefaults.standard.string(forKey: "samantha.voiceSession") ?? UUID().uuidString
    private(set) var api: SamanthaAPI
    private(set) var heartbeat: HeartbeatService
    private var isForeground = true
    private var reconnectTask: Task<Void, Never>?
    private var glassesCancellable: AnyCancellable?
    private var lastVoiceGlasses = false
    private var voiceSynced = false
    private var consoleTask: Task<Void, Never>?
    private var seenHermes = ""
    private var seenBuild = ""
    private var seenVoice = ""
    private var seenMain = ""
    private var consoleWarned = false
    private var lastLoggedReply = ""

    var deviceID: String { DeviceIdentity.deviceID }
    var deviceName: String { DeviceIdentity.deviceName }
    var hostLabel: String {
        let host = URL(string: serverURL)?.host?.lowercased() ?? ""
        if host.hasPrefix("100.") { return "TAILSCALE" }
        if host.hasPrefix("192.168.") || host.hasPrefix("10.") { return "LAN" }
        return host.isEmpty ? "CUSTOM" : "CUSTOM"
    }

    init() {
        let url = UserDefaults.standard.string(forKey: AppConfig.Keys.serverURL) ?? AppConfig.defaultServerURL
        let auth = UserDefaults.standard.bool(forKey: AppConfig.Keys.authEnabled)
        let interval = UserDefaults.standard.object(forKey: AppConfig.Keys.heartbeatInterval) as? Double
            ?? AppConfig.defaultHeartbeatInterval
        self.serverURL = url
        self.authEnabled = auth
        self.heartbeatInterval = interval
        let token = KeychainStore.get(account: AppConfig.Keys.apiTokenKeychain) ?? ""
        self.apiToken = token

        let client = SamanthaAPI(baseURL: url, authEnabled: auth, apiToken: token)
        self.api = client
        self.heartbeat = HeartbeatService(
            api: client,
            telemetry: telemetry,
            glasses: metaGlasses,
            intervalSeconds: interval
        )

        if UserDefaults.standard.string(forKey: "samantha.voiceSession") == nil {
            UserDefaults.standard.set(voiceSessionID, forKey: "samantha.voiceSession")
        }
        voice.onCommand = { [weak self] text in
            guard let self else { return nil }
            do {
                let response = try await self.api.sendCommand(deviceID: self.deviceID, sessionID: self.voiceSessionID, text: text)
                print("[WearableVoice] intent=\(response.intent)")
                return SpokenReply(
                    reply: response.reply,
                    intent: response.intent,
                    apiMs: response.latencyMs,
                    needsConfirmation: response.needsConfirmation,
                    speak: response.speak,
                    audioPath: response.tts?.audioURL,
                    gpu: response.tts?.gpu,
                    responseMode: response.responseMode,
                    mood: response.mood,
                    llmMs: response.llmMs,
                    f5FirstChunkMs: response.f5FirstChunkMs,
                    generation: response.generation,
                    followUpSeconds: response.followUpSeconds,
                    ackDelayMs: response.ackDelayMs,
                    llmFirstTokenMs: response.llmFirstTokenMs,
                    firstSentenceMs: response.firstSentenceMs
                )
            } catch {
                if self.isBenignCancellation(error) { return nil }
                self.lastError = error.localizedDescription
                print("[WearableVoice] command failed \(error.localizedDescription)")
                return nil
            }
        }
        voice.fetchAudio = { [weak self] path in
            guard let self else { throw URLError(.cancelled) }
            return try await self.api.fetchAudio(path: path)
        }
        glassesCancellable = metaGlasses.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
            Task { @MainActor in
                guard let self else { return }
                let connected = self.metaGlasses.glassesConnected
                guard connected != self.lastVoiceGlasses || !self.voiceSynced else { return }
                self.lastVoiceGlasses = connected
                self.voiceSynced = true
                self.voice.setForeground(self.isForeground, glassesConnected: connected)
            }
        }
    }

    func onAppear() {
        metaGlasses.configure()
        telemetry.start()
        applySettingsToAPI()
        startSession()
        startConsolePoll()
        refreshProjects()
        note("SYSTEM", "console open")
    }

    func onResignActive() {
        isForeground = false
        metaGlasses.suspendOnBackground()
        heartbeat.stop()
        voice.setForeground(false, glassesConnected: false)
        voice.disconnectEvents()
        consoleTask?.cancel()
        #if DEBUG
        print("[Lifecycle] resign active — heartbeat suspended, Meta camera stopped")
        #endif
        Task {
            try? await api.disconnect(deviceID: DeviceIdentity.deviceID)
        }
    }

    func onBecomeActive() {
        isForeground = true
        #if DEBUG
        print("[Lifecycle] become active — Samantha reconnect + Meta state re-eval")
        #endif
        Task {
            // Does not re-run Meta registration unless incomplete (one auto-retry).
            await metaGlasses.restoreOnForeground()
        }
        // Cancels prior reconnect Task; HeartbeatService.start() stops any prior loop first.
        startSession()
        syncVoice()
        startConsolePoll()
    }

    func syncVoice() {
        voice.setForeground(isForeground, glassesConnected: metaGlasses.glassesConnected)
        if isForeground {
            voice.connectEvents(baseURL: serverURL)
            if metaGlasses.glassesConnected && connectionState == .connected {
                voice.speakConnectedGreeting()
            }
        }
    }

    func applySettingsToAPI() {
        Task {
            await api.update(baseURL: serverURL, authEnabled: authEnabled, apiToken: apiToken)
        }
        heartbeat.update(api: api, intervalSeconds: heartbeatInterval)
    }

    func saveSettingsAndReconnect() {
        applySettingsToAPI()
        registered = false
        startSession()
    }

    func startSession() {
        reconnectTask?.cancel()
        reconnectTask = Task { [weak self] in
            await self?.connectRegisterAndPulse()
        }
    }

    func testConnection() {
        Task {
            await runTestConnection()
        }
    }

    func connectMetaGlasses() {
        Task {
            glassesActionBusy = true
            defer { glassesActionBusy = false }
            await metaGlasses.connectOrRegister()
        }
    }

    func disconnectMetaGlasses() {
        Task {
            glassesActionBusy = true
            defer { glassesActionBusy = false }
            await metaGlasses.disconnect()
        }
    }

    func testCamera() {
        Task {
            glassesActionBusy = true
            defer { glassesActionBusy = false }
            do {
                let data = try await metaGlasses.capturePhoto()
                photoPreviewVisible = metaGlasses.lastPhotoImage != nil
                testResult = "Camera capture OK · \(data.count) bytes"
                #if DEBUG
                print("[Dashboard] camera JPEG bytes=\(data.count) (content not logged)")
                #endif
            } catch {
                testResult = "Camera: \(error.localizedDescription)"
                lastError = error.localizedDescription
            }
        }
    }

    func dismissPhotoPreview() {
        photoPreviewVisible = false
        metaGlasses.clearPhotoPreview()
    }

    private func connectRegisterAndPulse() async {
        guard isForeground else { return }
        connectionState = .connecting
        lastError = nil
        applySettingsToAPI()

        do {
            #if DEBUG
            print("[Session] health check url=\(serverURL)")
            #endif
            let (health, ms) = try await api.health()
            latencyMs = ms
            heartbeat.setLatency(ms)
            lastHealthAt = Date()
            serverService = health.service
            serverAPIVersion = health.version
            guard health.isOK else {
                connectionState = .error
                lastError = "Health status: \(health.status)"
                heartbeat.stop()
                return
            }
            connectionState = .connected

            if !registered {
                #if DEBUG
                print("[Session] registering \(DeviceIdentity.deviceID)")
                #endif
                let reg = try await api.register(DeviceIdentity.registrationPayload())
                registered = reg.registered ?? true
                if let interval = reg.heartbeatIntervalSeconds, interval > 0 {
                    heartbeatInterval = Double(interval)
                    heartbeat.update(api: api, intervalSeconds: heartbeatInterval)
                }
                #if DEBUG
                print("[Session] registered ok")
                #endif
            }

            if isForeground && !heartbeat.isActive {
                heartbeat.start()
            }
        } catch {
            if Task.isCancelled || isBenignCancellation(error) { return }
            connectionState = .error
            lastError = error.localizedDescription
            registered = false
            heartbeat.stop()
            #if DEBUG
            print("[Session] FAIL \(error.localizedDescription)")
            #endif
        }
    }

    private func isBenignCancellation(_ error: Error) -> Bool {
        if error is CancellationError { return true }
        if let url = error as? URLError, url.code == .cancelled { return true }
        let ns = error as NSError
        return ns.domain == NSURLErrorDomain && ns.code == NSURLErrorCancelled
    }

    private func runTestConnection() async {
        testResult = "Testing…"
        do {
            let (health, ms) = try await api.health()
            latencyMs = ms
            heartbeat.setLatency(ms)
            testResult = health.isOK
                ? "OK · \(Int(ms)) ms · \(health.service ?? "samantha-wearable")"
                : "Unexpected status: \(health.status)"
        } catch {
            testResult = "Failed: \(error.localizedDescription)"
        }
    }

    var lastHeartbeatAgeText: String {
        guard let sent = heartbeat.lastSentAt else { return "—" }
        let age = Date().timeIntervalSince(sent)
        if age < 10 { return String(format: "%.1f sec", age) }
        return String(format: "%.0f sec", age)
    }

    var batteryText: String {
        guard let pct = telemetry.batteryPercent else { return "N/A" }
        return String(format: "%.0f%%", pct)
    }

    var chargingText: String {
        guard let c = telemetry.charging else { return "N/A" }
        return c ? "YES" : "NO"
    }

    var networkText: String {
        switch telemetry.networkKind {
        case "wifi": return "Wi-Fi"
        case "cellular": return "Cellular"
        default: return "Unknown"
        }
    }

    var glassesBatteryText: String {
        guard metaGlasses.glassesConnected else { return "—" }
        guard let pct = metaGlasses.glassesBatteryPercent else { return "N/A" }
        return String(format: "%.0f%%", pct)
    }

    var metaTrailingColor: Color {
        switch metaGlasses.connectionState {
        case .connected: return Color(red: 0.95, green: 0.54, blue: 0.0)
        case .connecting, .idle: return Color(red: 0.95, green: 0.63, blue: 0.11)
        case .error, .unsupported: return Color(red: 0.89, green: 0.36, blue: 0.20)
        case .disconnected: return Color(white: 0.45)
        }
    }

    var nodeState: String {
        switch connectionState {
        case .connected: return lastError == nil ? "NOMINAL" : "DEGRADED"
        case .connecting: return "LINKING"
        case .error: return "FAULT"
        case .disconnected: return "OFFLINE"
        }
    }

    func note(_ channel: String, _ message: String) {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        events.append(ConsoleEvent(at: Date(), channel: channel, message: trimmed))
        if events.count > 200 {
            events.removeFirst(events.count - 200)
        }
    }

    func noteReply(_ text: String) {
        guard text != lastLoggedReply else { return }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        lastLoggedReply = trimmed
        terminal.append(trimmed)
        if terminal.count > 80 { terminal.removeFirst(terminal.count - 80) }
        note("VOICE", trimmed)
    }

    func route(forShortcut raw: String) -> ConsoleRoute? {
        switch raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "home": return nil
        case "hermes": return .hermes
        case "voice": return .voice
        case "projects": return .projects
        case "system": return .system
        case "models": return .models
        case "gpus", "gpu": return .gpus
        case "logs", "log": return .logs
        case "settings": return .settings
        case "appearance": return .appearance
        case "glasses", "wearable": return .wearable
        default: return nil
        }
    }

    func submitConsole(_ raw: String) {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        let routed: String
        if commandTarget == "HERMES" && !text.lowercased().contains("hermes") {
            routed = "hermes \(text)"
        } else {
            routed = text
        }
        terminal.append("> \(routed)")
        note("SYSTEM", routed)
        voice.sendTypedCommand(routed)
    }

    func interruptHermes() {
        voice.stopSpeaking()
        terminal.append("local speech stop. Hermes has no shell interrupt on this phone.")
        note("HERMES", "local interrupt")
    }

    func reconnectEvents() {
        voice.disconnectEvents()
        voice.connectEvents(baseURL: serverURL)
        note("SYSTEM", "event socket reconnect")
    }

    func startConsolePoll() {
        consoleTask?.cancel()
        consoleTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refreshConsole()
                let seconds = max(self?.heartbeatInterval ?? 8, 8)
                try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            }
        }
    }

    func refreshConsole() async {
        do {
            var data = try await api.console()
            if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               (obj["ready"] as? Bool) != true {
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                data = try await api.console()
            }
            applyConsole(data)
            consoleWarned = false
        } catch {
            if isBenignCancellation(error) { return }
            if !consoleWarned {
                consoleWarned = true
                note("SYSTEM", "console unavailable")
            }
        }
    }

    func refreshProjects() {
        Task { await loadProjects() }
    }

    func loadProject(_ id: String) async -> ProjectRecord? {
        do {
            let data = try await api.projectStatus(id)
            guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
            let record = parseProject(obj["project"] as? [String: Any] ?? obj)
            if let index = projects.firstIndex(where: { $0.id == record.id }) {
                projects[index] = record
            }
            return record
        } catch {
            return projects.first { $0.id == id }
        }
    }

    private func loadProjects() async {
        do {
            let data = try await api.projects()
            guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let rows = obj["projects"] as? [[String: Any]] else { return }
            projects = rows.map(parseProject)
        } catch {
            if isBenignCancellation(error) { return }
            note("SYSTEM", "project list unavailable")
        }
    }

    private func applyConsole(_ data: Data) {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
        var next = ConsoleSnapshot()
        next.ready = obj["ready"] as? Bool ?? false
        next.host = obj["host"] as? String ?? ""
        next.ageSec = obj["age_sec"] as? Double
        if let rows = obj["gpus"] as? [[String: Any]] {
            next.gpus = rows.compactMap { row in
                guard let id = intValue(row["id"]) else { return nil }
                return GPUReading(
                    id: id,
                    temp: doubleValue(row["temp_c"]),
                    power: doubleValue(row["power_w"]),
                    vramUsed: doubleValue(row["vram_used_mb"]),
                    vramTotal: doubleValue(row["vram_total_mb"]),
                    util: doubleValue(row["utilization"])
                )
            }
        }
        if let hermes = obj["hermes"] as? [String: Any] {
            next.hermesState = hermes["state"] as? String ?? ""
            next.hermesDetail = hermes["detail"] as? String ?? ""
            next.hermesPID = intValue(hermes["pid"])
        }
        if let models = obj["models"] as? [String: Any] {
            if let main = models["main"] as? [String: Any] {
                next.mainName = main["name"] as? String ?? ""
                next.mainUnit = main["unit"] as? String ?? ""
                next.mainUp = main["up"] as? Bool
            }
            if let helper = models["helper"] as? [String: Any] {
                next.helperName = helper["name"] as? String ?? ""
                next.helperUnit = helper["unit"] as? String ?? ""
                next.helperUp = helper["up"] as? Bool
            }
            if let voice = models["voice"] as? [String: Any] {
                next.voiceUp = voice["up"] as? Bool
            }
            if let stt = models["stt"] as? [String: Any] {
                next.sttUnit = stt["unit"] as? String ?? ""
                next.sttUp = stt["up"] as? Bool
            }
        }
        if let build = obj["build"] as? [String: Any] {
            next.buildName = build["name"] as? String ?? ""
            next.buildConclusion = build["conclusion"] as? String ?? build["status"] as? String ?? ""
        }
        let previous = console
        console = next
        guard next.ready else { return }
        observeChange("HERMES", previous: seenHermes, next: next.hermesState)
        seenHermes = next.hermesState
        let buildLine = [next.buildConclusion, next.buildName].filter { !$0.isEmpty }.joined(separator: " ")
        observeChange("BUILD", previous: seenBuild, next: buildLine)
        seenBuild = buildLine
        let voiceLine = next.voiceUp == true ? "READY" : (next.voiceUp == false ? "OFFLINE" : "")
        observeChange("VOICE", previous: seenVoice, next: voiceLine)
        seenVoice = voiceLine
        let mainLine = next.mainUp == true ? "ACTIVE" : (next.mainUp == false ? "OFFLINE" : "")
        observeChange("SYSTEM", previous: seenMain, next: mainLine.isEmpty ? "" : "main model \(mainLine)")
        seenMain = mainLine.isEmpty ? "" : "main model \(mainLine)"
        if previous.gpus.contains(where: { $0.temp >= 80 }) == false {
            if let hot = next.gpus.first(where: { $0.temp >= 80 }) {
                note("GPU", String(format: "G%d %.0fC", hot.id, hot.temp))
            }
        }
    }

    private func observeChange(_ channel: String, previous: String, next: String) {
        guard !next.isEmpty, next != previous else { return }
        note(channel, next)
    }

    private func parseProject(_ row: [String: Any]) -> ProjectRecord {
        let git = row["git_status"] as? String ?? ""
        let branch = git.hasPrefix("## ") ? git.dropFirst(3).split(separator: ".").first.map(String.init) ?? "" : ""
        let build = row["last_build"] as? [String: Any] ?? [:]
        return ProjectRecord(
            id: row["project_id"] as? String ?? "",
            name: row["name"] as? String ?? (row["project_id"] as? String ?? "project"),
            branch: branch,
            gitStatus: git,
            dirtyCount: intValue(row["dirty_count"]) ?? 0,
            lastCommit: row["last_commit"] as? String ?? "",
            buildConclusion: build["conclusion"] as? String ?? "",
            buildName: build["name"] as? String ?? "",
            exists: row["exists"] as? Bool ?? true
        )
    }

    private func intValue(_ value: Any?) -> Int? {
        if let value = value as? Int { return value }
        if let value = value as? Double { return Int(value) }
        if let value = value as? String { return Int(value) }
        return nil
    }

    private func doubleValue(_ value: Any?) -> Double {
        if let value = value as? Double { return value }
        if let value = value as? Int { return Double(value) }
        if let value = value as? String { return Double(value) ?? 0 }
        return 0
    }
}
