// Models/DeviceRegistration.swift
import Foundation

struct DeviceRegistration: Codable, Equatable {
    let deviceId: String
    let deviceName: String
    let deviceType: String
    let platform: String
    let appVersion: String
    let glassesConnected: Bool
    let glassesName: String?
    let capabilities: [String]

    enum CodingKeys: String, CodingKey {
        case deviceId = "device_id"
        case deviceName = "device_name"
        case deviceType = "device_type"
        case platform
        case appVersion = "app_version"
        case glassesConnected = "glasses_connected"
        case glassesName = "glasses_name"
        case capabilities
    }
}

struct RegistrationResponse: Codable, Equatable {
    let ok: Bool?
    let deviceId: String?
    let registered: Bool?
    let heartbeatIntervalSeconds: Int?
    let error: String?

    enum CodingKeys: String, CodingKey {
        case ok
        case deviceId = "device_id"
        case registered
        case heartbeatIntervalSeconds = "heartbeat_interval_seconds"
        case error
    }
}
