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
                    gpu: response.tts?.gpu
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
                self?.voice.setForeground(self?.isForeground ?? false, glassesConnected: self?.metaGlasses.glassesConnected ?? false)
            }
        }
    }

    func onAppear() {
        metaGlasses.configure()
        telemetry.start()
        applySettingsToAPI()
        startSession()
    }

    func onResignActive() {
        isForeground = false
        metaGlasses.suspendOnBackground()
        heartbeat.stop()
        voice.setForeground(false, glassesConnected: false)
        voice.disconnectEvents()
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
}
