// Services/MetaGlassesService.swift
// Real Meta Wearables DAT integration (MWDATCore + MWDATCamera).
// Hardened for physical validation against meta-wearables-dat-ios 1.0.0.

import Foundation
import UIKit
import Combine
import MWDATCore
import MWDATCamera

@MainActor
final class MetaGlassesService: ObservableObject, GlassesTelemetryProviding {
    enum RegistrationUIState: String {
        case unknown = "UNKNOWN"
        case available = "AVAILABLE"
        case registering = "REGISTERING"
        case registered = "REGISTERED"
        case unavailable = "UNAVAILABLE"
    }

    enum ConnectionUIState: String {
        case idle = "IDLE"
        case connecting = "CONNECTING"
        case connected = "CONNECTED"
        case disconnected = "DISCONNECTED"
        case unsupported = "UNSUPPORTED"
        case error = "ERROR"
    }

    @Published private(set) var isConfigured = false
    @Published private(set) var registrationState: RegistrationUIState = .unknown
    @Published private(set) var connectionState: ConnectionUIState = .idle
    @Published private(set) var connectedDeviceName: String?
    @Published private(set) var connectedDeviceId: String?
    @Published private(set) var linkStateText: String = "—"
    @Published private(set) var compatibilityText: String = "—"
    @Published private(set) var glassesBatteryPercent: Double?
    @Published private(set) var cameraLabel: CapabilityLabel = .unavailable
    @Published private(set) var microphoneLabel: CapabilityLabel = .unavailable
    @Published private(set) var audioOutputLabel: CapabilityLabel = .unavailable
    @Published private(set) var cameraPermission: PermissionProbe = .unknown
    @Published private(set) var microphonePermission: PermissionProbe = .unknown
    @Published private(set) var lastError: String?
    @Published private(set) var lastPhotoImage: UIImage?
    @Published private(set) var lastPhotoByteCount: Int = 0
    @Published private(set) var isCapturingPhoto = false
    @Published private(set) var isStreamingPreview = false
    @Published private(set) var requiresFirmwareUpdate = false
    @Published private(set) var sessionStateText: String = "—"
    @Published var previewFrame: UIImage?

    var glassesConnected: Bool { connectionState == .connected }
    var cameraAvailable: Bool { cameraPermission == .granted }
    var microphoneAvailable: Bool { microphonePermission == .granted }
    var audioOutputAvailable: Bool { audioOutputLabel == .ready }

    var statusText: String {
        if !isConfigured { return "SDK ERROR" }
        if connectionState == .connected { return connectionState.rawValue }
        if registrationState == .registering { return registrationState.rawValue }
        if connectionState == .connecting { return connectionState.rawValue }
        if registrationState == .registered { return connectionState.rawValue }
        return registrationState.rawValue
    }

    private var deviceSession: DeviceSession?
    private var deviceSelector: AutoDeviceSelector?
    private var camera: Camera?
    private var stream: Stream?
    private var deviceStateToken: AnyListenerToken?
    private var compatibilityToken: AnyListenerToken?
    private var linkStateToken: AnyListenerToken?
    private let streamTokens = ListenerTokenBag()
    private var registrationTask: Task<Void, Never>?
    private var devicesTask: Task<Void, Never>?
    private var sessionStateTask: Task<Void, Never>?
    private var sessionErrorTask: Task<Void, Never>?
    private var activeDeviceTask: Task<Void, Never>?
    private var photoContinuation: CheckedContinuation<Data, Error>?
    /// One automatic registration retry after returning from Meta AI without becoming registered.
    private var registrationAutoRetryUsed = false
    private var observersStarted = false

    // MARK: - Configure / observe

    func configure() {
        guard !isConfigured else {
            log("configure skipped — already configured")
            return
        }
        do {
            try Wearables.configure()
            isConfigured = true
            lastError = nil
            registrationState = mapRegistration(Wearables.shared.registrationState)
            startObservers()
            log("Wearables.configure() OK registration=\(registrationState.rawValue)")
        } catch {
            isConfigured = false
            lastError = "SDK configure failed: \(error.localizedDescription)"
            log("configure FAIL \(error.localizedDescription)")
        }
    }

    private func startObservers() {
        guard !observersStarted else {
            log("observers already started — skip")
            return
        }
        observersStarted = true
        registrationTask?.cancel()
        devicesTask?.cancel()
        let wearables = Wearables.shared

        registrationTask = Task { [weak self] in
            for await state in wearables.registrationStateStream() {
                guard let self else { return }
                self.applyRegistrationState(state)
            }
        }

        devicesTask = Task { [weak self] in
            for await deviceIds in wearables.devicesStream() {
                guard let self else { return }
                self.handleDevicesUpdate(deviceIds)
            }
        }
        log("observers started (registration + devices)")
    }

    private func mapRegistration(_ state: RegistrationState) -> RegistrationUIState {
        switch state {
        case .registered: return .registered
        case .registering: return .registering
        case .available: return .available
        case .unavailable: return .unavailable
        @unknown default: return .unknown
        }
    }

    private func applyRegistrationState(_ state: RegistrationState) {
        registrationState = mapRegistration(state)
        if state == .unavailable {
            connectionState = .unsupported
        }
        if state == .registered {
            registrationAutoRetryUsed = false
        }
        log("registrationState=\(registrationState.rawValue)")
    }

    private func handleDevicesUpdate(_ deviceIds: [DeviceIdentifier]) {
        let wearables = Wearables.shared
        log("devicesStream count=\(deviceIds.count)")

        if let firstId = deviceIds.first,
           let device = wearables.deviceForIdentifier(firstId) {
            applyDeviceSnapshot(device, id: firstId)
        } else if connectionState != .connecting && connectionState != .connected {
            connectedDeviceName = nil
            connectedDeviceId = nil
            linkStateText = "—"
            compatibilityText = "—"
            glassesBatteryPercent = nil
            requiresFirmwareUpdate = false
            log("no devices in devicesStream")
        }
    }

    private func applyDeviceSnapshot(_ device: Device, id: DeviceIdentifier) {
        connectedDeviceId = String(describing: id)
        if connectionState != .connected || connectedDeviceName == nil {
            connectedDeviceName = device.nameOrId()
        }
        linkStateText = String(describing: device.linkState).uppercased()
        let compatibility = device.compatibility()
        compatibilityText = String(describing: compatibility).uppercased()
        requiresFirmwareUpdate = (compatibility == .deviceUpdateRequired)
        if let level = device.batteryLevel {
            glassesBatteryPercent = Double(level)
        }
        monitorCompatibility(for: device)
        monitorLinkState(for: device)
        log(
            "device name=\(device.nameOrId()) id=\(connectedDeviceId ?? "?") link=\(linkStateText) compat=\(compatibilityText) battery=\(device.batteryLevel.map(String.init) ?? "nil")"
        )
    }

    private func monitorCompatibility(for device: Device) {
        compatibilityToken = nil
        requiresFirmwareUpdate = (device.compatibility() == .deviceUpdateRequired)
        if requiresFirmwareUpdate {
            lastError = "\(device.nameOrId()) needs a firmware update"
        }
        compatibilityToken = device.addCompatibilityListener { [weak self] value in
            Task { @MainActor in
                guard let self else { return }
                self.compatibilityText = String(describing: value).uppercased()
                self.requiresFirmwareUpdate = (value == .deviceUpdateRequired)
                self.log("compatibility=\(self.compatibilityText)")
                if value == .deviceUpdateRequired {
                    self.lastError = "Glasses firmware update required"
                }
            }
        }
    }

    private func monitorLinkState(for device: Device) {
        linkStateToken = nil
        linkStateText = String(describing: device.linkState).uppercased()
        linkStateToken = device.addLinkStateListener { [weak self] value in
            Task { @MainActor in
                guard let self else { return }
                self.linkStateText = String(describing: value).uppercased()
                self.log("linkState=\(self.linkStateText)")
            }
        }
    }

    // MARK: - URL callback (Meta AI)

    func handleOpenURL(_ url: URL) async {
        guard
            let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
            components.queryItems?.contains(where: { $0.name == "metaWearablesAction" }) == true
        else {
            log("onOpenURL ignored (no metaWearablesAction) host=\(url.host ?? "-")")
            return
        }
        let action = components.queryItems?.first(where: { $0.name == "metaWearablesAction" })?.value ?? "?"
        log("callback received action=\(action)")
        do {
            _ = try await Wearables.shared.handleUrl(url)
            lastError = nil
            log("handleUrl OK registration=\(mapRegistration(Wearables.shared.registrationState).rawValue)")
        } catch let error as RegistrationError {
            lastError = "Meta callback failed: \(error.description)"
            log("handleUrl RegistrationError \(error.description)")
        } catch {
            lastError = "Meta callback failed: \(error.localizedDescription)"
            log("handleUrl FAIL \(error.localizedDescription)")
        }
    }

    // MARK: - Registration

    func register() async {
        guard isConfigured else {
            lastError = "SDK not configured"
            return
        }
        if registrationState == .registering {
            log("register skipped — already registering")
            return
        }
        log("startRegistration()")
        do {
            try await Wearables.shared.startRegistration()
            lastError = nil
            log("startRegistration returned — waiting for Meta AI callback")
        } catch let error as RegistrationError {
            lastError = "Registration failed: \(error.description)"
            log("startRegistration RegistrationError \(error.description)")
        } catch {
            lastError = "Registration failed: \(error.localizedDescription)"
            log("startRegistration FAIL \(error.localizedDescription)")
        }
    }

    func unregister() async {
        guard isConfigured else { return }
        do {
            try await Wearables.shared.startUnregistration()
            await disconnect()
            lastError = nil
        } catch let error as UnregistrationError {
            lastError = "Unregister failed: \(error.description)"
        } catch {
            lastError = "Unregister failed: \(error.localizedDescription)"
        }
    }

    /// User-facing CONNECT: register with Meta AI if needed, then open a device session.
    func connectOrRegister() async {
        if registrationState == .registered {
            await connect()
            return
        }
        registrationAutoRetryUsed = false
        await register()
    }

    // MARK: - Session connect / disconnect

    func connect() async {
        guard isConfigured else {
            lastError = "SDK not configured"
            return
        }
        if registrationState != .registered {
            lastError = "Register with Meta AI first"
            return
        }

        // Reuse an already live session — never create a duplicate.
        if let existing = deviceSession {
            switch existing.state {
            case .started:
                connectionState = .connected
                sessionStateText = "STARTED"
                log("connect reused existing started session")
                await refreshCapabilities()
                return
            case .starting, .paused:
                connectionState = .connecting
                sessionStateText = String(describing: existing.state).uppercased()
                log("connect reused in-flight session state=\(sessionStateText)")
                return
            default:
                log("tearing down stale session state=\(existing.state)")
                teardownSession()
            }
        }

        if connectionState == .connected || connectionState == .connecting {
            return
        }

        connectionState = .connecting
        lastError = nil
        log("createSession(AutoDeviceSelector)")

        do {
            let wearables = Wearables.shared
            let selector = AutoDeviceSelector(wearables: wearables)
            deviceSelector = selector

            activeDeviceTask?.cancel()
            activeDeviceTask = Task { [weak self] in
                for await deviceId in selector.activeDeviceStream() {
                    guard let self else { return }
                    if let deviceId, let device = wearables.deviceForIdentifier(deviceId) {
                        self.applyDeviceSnapshot(device, id: deviceId)
                    } else {
                        self.log("activeDeviceStream => nil")
                    }
                }
            }

            let session = try wearables.createSession(deviceSelector: selector)
            deviceSession = session

            sessionStateTask?.cancel()
            sessionStateTask = Task { [weak self] in
                for await state in session.stateStream() {
                    guard let self else { return }
                    self.handleSessionState(state)
                }
            }

            sessionErrorTask?.cancel()
            sessionErrorTask = Task { [weak self] in
                for await error in session.errorStream() {
                    guard let self else { return }
                    self.handleSessionError(error)
                }
            }

            do {
                try session.start()
                log("session.start() OK")
            } catch let error as DeviceSessionError {
                handleSessionError(error)
                teardownSession()
                connectionState = connectionState == .unsupported ? .unsupported : .error
                return
            }

            let deadline = Date().addingTimeInterval(25)
            while Date() < deadline {
                if connectionState == .connected { break }
                if connectionState == .error || connectionState == .unsupported { break }
                try await Task.sleep(nanoseconds: 100_000_000)
            }

            if connectionState == .connecting {
                if session.device != nil || session.state == .started {
                    await markConnected(session: session)
                } else {
                    connectionState = .error
                    lastError = lastError ?? "Timed out waiting for glasses session"
                    log("session timeout — no device; devices may be empty / incompatible")
                    teardownSession()
                }
            }

            await refreshCapabilities()
        } catch let error as DeviceSessionError {
            connectionState = .error
            lastError = "Connect failed: \(error.localizedDescription)"
            log("createSession DeviceSessionError \(error.localizedDescription)")
            teardownSession()
        } catch {
            connectionState = .error
            lastError = "Connect failed: \(error.localizedDescription)"
            log("createSession FAIL \(error.localizedDescription)")
            teardownSession()
        }
    }

    private func handleSessionError(_ error: DeviceSessionError) {
        let text = String(describing: error)
        if text.contains("sessionAlreadyExists") {
            lastError = "Device session already exists"
            log("sessionAlreadyExists")
        } else if text.contains("datAppOnTheGlassesUpdateRequired") {
            lastError = "DAT glasses app update required"
            Task { try? await Wearables.shared.openDATGlassesAppUpdate() }
        } else if text.contains("insufficientSDKVersion") {
            connectionState = .unsupported
            lastError = "App SDK too old for these glasses"
        } else if text.lowercased().contains("battery") {
            lastError = "Glasses battery too low"
        } else if text.lowercased().contains("thermal") {
            lastError = "Glasses thermal limit"
        } else if text.contains("noEligibleDevice") {
            lastError = "No eligible Meta glasses found"
            log("noEligibleDevice — check devicesStream / compatibility / link")
        } else {
            lastError = error.localizedDescription
        }
        log("session error \(text)")
    }

    private func handleSessionState(_ state: DeviceSessionState) {
        sessionStateText = String(describing: state).uppercased()
        log("sessionState=\(sessionStateText)")
        switch state {
        case .starting:
            connectionState = .connecting
        case .started:
            if let session = deviceSession {
                Task { await markConnected(session: session) }
            }
        case .paused:
            break
        case .stopping:
            break
        case .stopped:
            connectionState = .disconnected
            glassesBatteryPercent = nil
            cameraLabel = .unavailable
            microphoneLabel = .unavailable
            audioOutputLabel = .unavailable
            cameraPermission = .unknown
            microphonePermission = .unknown
            stopCameraPipeline()
            deviceSession = nil
            sessionStateText = "STOPPED"
        case .idle:
            break
        @unknown default:
            break
        }
    }

    private func markConnected(session: DeviceSession) async {
        connectionState = .connected
        sessionStateText = "STARTED"
        if let device = session.device {
            // Prefer live session device; id may already be set from streams.
            connectedDeviceName = device.nameOrId()
            if let level = device.batteryLevel {
                glassesBatteryPercent = Double(level)
            }
            linkStateText = String(describing: device.linkState).uppercased()
            compatibilityText = String(describing: device.compatibility()).uppercased()
            deviceStateToken = nil
            deviceStateToken = device.addDeviceStateListener { [weak self] _ in
                Task { @MainActor in
                    guard let self else { return }
                    if let level = self.deviceSession?.device?.batteryLevel {
                        self.glassesBatteryPercent = Double(level)
                        self.log("battery=\(level)")
                    }
                }
            }
            monitorCompatibility(for: device)
            monitorLinkState(for: device)
            log("CONNECTED device=\(device.nameOrId()) battery=\(device.batteryLevel.map(String.init) ?? "nil")")
        } else {
            connectedDeviceName = connectedDeviceName ?? "Meta Glasses"
            log("CONNECTED without session.device snapshot")
        }
        await refreshCapabilities()
    }

    func disconnect() async {
        log("disconnect()")
        stopCameraPipeline()
        teardownSession()
        connectionState = .disconnected
        glassesBatteryPercent = nil
        cameraLabel = .unavailable
        microphoneLabel = .unavailable
        audioOutputLabel = .unavailable
        cameraPermission = .unknown
        microphonePermission = .unknown
        previewFrame = nil
        isStreamingPreview = false
        sessionStateText = "—"
    }

    private func teardownSession() {
        sessionStateTask?.cancel()
        sessionStateTask = nil
        sessionErrorTask?.cancel()
        sessionErrorTask = nil
        activeDeviceTask?.cancel()
        activeDeviceTask = nil
        deviceStateToken = nil
        compatibilityToken = nil
        linkStateToken = nil
        streamTokens.clear()
        camera?.stop()
        deviceSession?.stop()
        stream = nil
        camera = nil
        deviceSession = nil
        deviceSelector = nil
        log("session torn down")
    }

    // MARK: - Capabilities / permissions

    func refreshCapabilities() async {
        guard isConfigured else {
            cameraLabel = .unavailable
            microphoneLabel = .unavailable
            audioOutputLabel = .unavailable
            cameraPermission = .unknown
            microphonePermission = .unknown
            return
        }

        guard glassesConnected else {
            cameraLabel = .unavailable
            microphoneLabel = .unavailable
            audioOutputLabel = .unavailable
            cameraPermission = .unknown
            microphonePermission = .unknown
            return
        }

        cameraPermission = await probePermission(.camera)
        microphonePermission = await probePermission(.microphone)
        cameraLabel = capabilityLabel(from: cameraPermission)
        microphoneLabel = capabilityLabel(from: microphonePermission)
        // No stable public audio-output probe in DAT 1.0.0 core/camera.
        audioOutputLabel = .unsupported
        log(
            "permissions camera=\(cameraPermission.rawValue) mic=\(microphonePermission.rawValue) audio=\(audioOutputLabel.rawValue)"
        )
    }

    private func probePermission(_ permission: Permission) async -> PermissionProbe {
        do {
            let status = try await Wearables.shared.checkPermissionStatus(permission)
            switch status {
            case .granted:
                return .granted
            case .denied:
                return .denied
            default:
                // notDetermined / limited / other → UNKNOWN until user acts
                return .unknown
            }
        } catch {
            log("permission \(permission) check error \(error.localizedDescription)")
            return .unavailable
        }
    }

    private func capabilityLabel(from probe: PermissionProbe) -> CapabilityLabel {
        switch probe {
        case .granted: return .ready
        case .denied, .unknown: return .permissionRequired
        case .unavailable: return .unavailable
        }
    }

    func requestCameraPermission() async {
        do {
            log("requestPermission(.camera)")
            let status = try await Wearables.shared.requestPermission(.camera)
            await refreshCapabilities()
            if status != .granted {
                lastError = "Camera permission not granted (\(cameraPermission.rawValue))"
            }
        } catch {
            lastError = "Camera permission failed: \(error.localizedDescription)"
            cameraPermission = .unavailable
        }
    }

    func openFirmwareUpdate() async {
        do {
            try await Wearables.shared.openFirmwareUpdate()
        } catch {
            lastError = error.localizedDescription
        }
    }

    // MARK: - Camera test

    func capturePhoto() async throws -> Data {
        guard glassesConnected, let session = deviceSession else {
            throw MetaGlassesError.notConnected
        }
        if isCapturingPhoto {
            throw MetaGlassesError.captureInFlight
        }

        log("capturePhoto begin session=\(sessionStateText)")
        let status = try await Wearables.shared.checkPermissionStatus(.camera)
        if status != .granted {
            let requested = try await Wearables.shared.requestPermission(.camera)
            guard requested == .granted else {
                cameraPermission = .denied
                cameraLabel = .permissionRequired
                throw MetaGlassesError.permissionDenied
            }
        }
        cameraPermission = .granted
        cameraLabel = .ready

        isCapturingPhoto = true
        defer { isCapturingPhoto = false }

        try await ensureStreamRunning(session: session)

        let data = try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Data, Error>) in
            if photoContinuation != nil {
                cont.resume(throwing: MetaGlassesError.captureInFlight)
                return
            }
            photoContinuation = cont
            guard let stream else {
                photoContinuation = nil
                cont.resume(throwing: MetaGlassesError.streamUnavailable)
                return
            }
            let started = stream.capturePhoto(format: .jpeg)
            log("capturePhoto(format:.jpeg) started=\(started)")
            if !started {
                photoContinuation = nil
                cont.resume(throwing: MetaGlassesError.captureNotStarted)
            }
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 15_000_000_000)
                if let pending = self.photoContinuation {
                    self.photoContinuation = nil
                    self.log("capture timeout")
                    pending.resume(throwing: MetaGlassesError.captureTimeout)
                }
            }
        }
        lastPhotoByteCount = data.count
        log("capture OK bytes=\(data.count)")
        return data
    }

    private func ensureStreamRunning(session: DeviceSession) async throws {
        if stream != nil, isStreamingPreview {
            log("stream already running")
            return
        }

        // If a prior camera exists but isn't streaming, stop before addCamera.
        if camera != nil {
            log("restarting camera pipeline")
            stopCameraPipeline()
        }

        streamTokens.clear()
        let config = StreamConfiguration(
            videoCodec: .raw,
            resolution: .low,
            frameRate: 24
        )
        guard let camera = try session.addCamera(config: config) else {
            throw MetaGlassesError.cameraUnavailable
        }
        self.camera = camera
        let stream = camera.stream
        self.stream = stream

        stream.statePublisher.listen { [weak self] state in
            Task { @MainActor in
                self?.isStreamingPreview = (state == .streaming)
                self?.log("streamState=\(state)")
            }
        }.store(in: streamTokens)

        stream.videoFramePublisher.listen { [weak self] frame in
            guard let image = frame.makeUIImage() else { return }
            Task { @MainActor in
                self?.previewFrame = image
            }
        }.store(in: streamTokens)

        stream.photoDataPublisher.listen { [weak self] photoData in
            Task { @MainActor in
                self?.handlePhotoData(photoData)
            }
        }.store(in: streamTokens)

        stream.errorPublisher.listen { [weak self] error in
            Task { @MainActor in
                self?.lastError = error.localizedDescription
                self?.log("stream error \(error.localizedDescription)")
                if let pending = self?.photoContinuation {
                    self?.photoContinuation = nil
                    pending.resume(throwing: error)
                }
            }
        }.store(in: streamTokens)

        stream.start()
        log("stream.start()")

        let deadline = Date().addingTimeInterval(12)
        while Date() < deadline {
            if isStreamingPreview { return }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        log("stream start wait elapsed without .streaming — capture may still succeed")
    }

    private func handlePhotoData(_ photoData: PhotoData) {
        let data = photoData.data
        lastPhotoByteCount = data.count
        if let image = UIImage(data: data) {
            lastPhotoImage = image
        }
        if let pending = photoContinuation {
            photoContinuation = nil
            pending.resume(returning: data)
        }
    }

    func stopCameraPipeline() {
        streamTokens.clear()
        camera?.stop()
        stream = nil
        camera = nil
        isStreamingPreview = false
        previewFrame = nil
        if let pending = photoContinuation {
            photoContinuation = nil
            pending.resume(throwing: MetaGlassesError.streamUnavailable)
        }
        log("camera pipeline stopped")
    }

    func restoreOnForeground() async {
        guard isConfigured else {
            configure()
            return
        }
        applyRegistrationState(Wearables.shared.registrationState)
        log("foreground restore registration=\(registrationState.rawValue) connection=\(connectionState.rawValue)")

        // Meta AI opened but registration never completed — one automatic retry.
        if registrationState == .available {
            if !registrationAutoRetryUsed {
                registrationAutoRetryUsed = true
                lastError = "Registration incomplete after Meta AI — retrying once"
                log("auto-retry registration once")
                await register()
            } else {
                lastError = "Registration incomplete — Meta AI may have opened without approval UI. Tap CONNECT to retry."
                log("auto-retry already used — waiting for manual CONNECT")
            }
        }

        await refreshCapabilities()
        if connectionState == .connected, deviceSession == nil {
            connectionState = .disconnected
            glassesBatteryPercent = nil
            cameraLabel = .unavailable
            microphoneLabel = .unavailable
            audioOutputLabel = .unavailable
            log("foreground: believed connected but session gone → disconnected")
        }
    }

    func suspendOnBackground() {
        log("background — stop camera pipeline (keep registration; no new session)")
        stopCameraPipeline()
    }

    func clearPhotoPreview() {
        lastPhotoImage = nil
        lastPhotoByteCount = 0
    }

    private func log(_ message: String) {
        #if DEBUG
        print("[MetaGlasses] \(message)")
        #endif
    }
}

enum MetaGlassesError: LocalizedError {
    case notConnected
    case permissionDenied
    case cameraUnavailable
    case streamUnavailable
    case captureInFlight
    case captureNotStarted
    case captureTimeout

    var errorDescription: String? {
        switch self {
        case .notConnected: return "Glasses are not connected"
        case .permissionDenied: return "Camera permission denied"
        case .cameraUnavailable: return "Camera capability unavailable on session"
        case .streamUnavailable: return "Camera stream unavailable"
        case .captureInFlight: return "A capture is already in progress"
        case .captureNotStarted: return "Capture did not start (try again)"
        case .captureTimeout: return "Photo capture timed out"
        }
    }
}
