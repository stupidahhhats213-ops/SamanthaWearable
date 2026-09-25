// Models/ServerHealth.swift
import Foundation

struct ServerHealth: Codable, Equatable {
    let status: String
    let service: String?
    let version: String?
    let uptimeSeconds: Int?
    let connectedDevices: Int?
    let timestamp: String?

    enum CodingKeys: String, CodingKey {
        case status
        case service
        case version
        case uptimeSeconds = "uptime_seconds"
        case connectedDevices = "connected_devices"
        case timestamp
    }

    var isOK: Bool { status.lowercased() == "ok" }
}
