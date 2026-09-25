// Services/HeartbeatService.swift
import Foundation

@MainActor
final class HeartbeatService: ObservableObject {
    @Published private(set) var isActive = false
    @Published private(set) var lastSentAt: Date?
    @Published private(set) var lastError: String?
    @Published private(set) var lastServerStatus: String?
    @Published private(set) var successCount = 0
    @Published private(set) var failureCount = 0

    private var task: Task<Void, Never>?
    private var api: SamanthaAPI
    private let telemetry: DeviceTelemetry
    private var glasses: GlassesTelemetryProviding
    private var intervalSeconds: Double
    private var latestLatencyMs: Double?

    init(
        api: SamanthaAPI,
        telemetry: DeviceTelemetry,
        glasses: GlassesTelemetryProviding,
        intervalSeconds: Double
    ) {
        self.api = api
        self.telemetry = telemetry
        self.glasses = glasses
        self.intervalSeconds = max(2.0, intervalSeconds)
    }

    func update(api: SamanthaAPI, intervalSeconds: Double) {
        self.api = api
        self.intervalSeconds = max(2.0, intervalSeconds)
    }

    func setGlasses(_ glasses: GlassesTelemetryProviding) {
        self.glasses = glasses
    }

    func setLatency(_ ms: Double?) {
        latestLatencyMs = ms
    }

    func start() {
        stop()
        isActive = true
        lastError = nil
        #if DEBUG
        print("[Heartbeat] starting loop interval=\(intervalSeconds)s device=\(DeviceIdentity.deviceID)")
        #endif
        task = Task { [weak self] in
            await self?.runLoop()
        }
    }

    func stop() {
        task?.cancel()
        task = nil
        isActive = false
        #if DEBUG
        print("[Heartbeat] stopped")
        #endif
    }

    private func runLoop() async {
        while !Task.isCancelled {
            await sendOnce()
            let ns = UInt64(intervalSeconds * 1_000_000_000)
            try? await Task.sleep(nanoseconds: ns)
        }
    }

    private func sendOnce() async {
        telemetry.refreshBattery()
        let connected = glasses.glassesConnected
        let payload = HeartbeatPayload(
            deviceId: DeviceIdentity.deviceID,
            batteryPercent: telemetry.batteryPercent,
            charging: telemetry.charging,
            network: telemetry.networkKind,
            latencyMs: latestLatencyMs,
            glassesConnected: connected,
            glassesBatteryPercent: connected ? glasses.glassesBatteryPercent : nil,
            cameraAvailable: connected ? glasses.cameraAvailable : false,
            microphoneAvailable: connected ? glasses.microphoneAvailable : false,
            audioOutputAvailable: connected ? glasses.audioOutputAvailable : false
        )
        do {
            let response = try await api.sendHeartbeat(payload)
            lastSentAt = Date()
            lastServerStatus = response.status
            lastError = nil
            successCount += 1
            #if DEBUG
            print(
                "[Heartbeat] OK status=\(response.status ?? "?") glasses=\(payload.glassesConnected) cam=\(payload.cameraAvailable) mic=\(payload.microphoneAvailable)"
            )
            #endif
        } catch {
            failureCount += 1
            lastError = error.localizedDescription
            #if DEBUG
            print("[Heartbeat] FAIL \(error.localizedDescription)")
            #endif
        }
    }
}
