// Models/HeartbeatPayload.swift
import Foundation

struct HeartbeatPayload: Codable, Equatable {
    let deviceId: String
    let batteryPercent: Double?
    let charging: Bool?
    let network: String?
    let latencyMs: Double?
    let glassesConnected: Bool
    let glassesBatteryPercent: Double?
    let cameraAvailable: Bool
    let microphoneAvailable: Bool
    let audioOutputAvailable: Bool

    enum CodingKeys: String, CodingKey {
        case deviceId = "device_id"
        case batteryPercent = "battery_percent"
        case charging
        case network
        case latencyMs = "latency_ms"
        case glassesConnected = "glasses_connected"
        case glassesBatteryPercent = "glasses_battery_percent"
        case cameraAvailable = "camera_available"
        case microphoneAvailable = "microphone_available"
        case audioOutputAvailable = "audio_output_available"
    }
}

struct HeartbeatResponse: Codable, Equatable {
    let ok: Bool?
    let deviceId: String?
    let status: String?
    let heartbeatAgeSec: Double?
    let error: String?

    enum CodingKeys: String, CodingKey {
        case ok
        case deviceId = "device_id"
        case status
        case heartbeatAgeSec = "heartbeat_age_sec"
        case error
    }
}

struct DisconnectRequest: Codable {
    let deviceId: String
    enum CodingKeys: String, CodingKey { case deviceId = "device_id" }
}

struct DisconnectResponse: Codable {
    let ok: Bool?
    let deviceId: String?
    let disconnected: Bool?
    let error: String?

    enum CodingKeys: String, CodingKey {
        case ok
        case deviceId = "device_id"
        case disconnected
        case error
    }
}
