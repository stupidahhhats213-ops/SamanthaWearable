// Models/WearableHealth.swift
import Foundation

struct WearableHealth: Codable, Equatable {
    let status: String?
    let aggregate: String?
    let service: String?
    let version: String?
    let uptimeSeconds: Int?
    let connectedDevices: Int?
    let database: String?
    let listener: ListenerHealth?
    let devices: DeviceCounts?
    let components: Components?

    enum CodingKeys: String, CodingKey {
        case status, aggregate, service, version, database, listener, devices, components
        case uptimeSeconds = "uptime_seconds"
        case connectedDevices = "connected_devices"
    }

    struct ListenerHealth: Codable, Equatable {
        let host: String?
        let port: Int?
        let running: Bool?
        let reachable: Bool?
        let status: String?
        let error: String?
    }

    struct DeviceCounts: Codable, Equatable {
        let registered: Int?
        let online: Int?
        let degraded: Int?
        let stale: Int?
        let offline: Int?
        let unknown: Int?
    }

    struct Components: Codable, Equatable {
        let api: String?
        let database: String?
        let heartbeats: String?
    }
}
