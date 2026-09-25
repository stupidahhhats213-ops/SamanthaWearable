// Services/GlassesTelemetryProviding.swift
import Foundation

/// Shared telemetry surface for Samantha heartbeats and dashboard UI.
@MainActor
protocol GlassesTelemetryProviding: AnyObject {
    var glassesConnected: Bool { get }
    var glassesBatteryPercent: Double? { get }
    var cameraAvailable: Bool { get }
    var microphoneAvailable: Bool { get }
    var audioOutputAvailable: Bool { get }
    var connectedDeviceName: String? { get }
}

/// Capability readiness for UI / heartbeat booleans.
enum CapabilityLabel: String {
    case ready = "READY"
    case unavailable = "UNAVAILABLE"
    case unsupported = "UNSUPPORTED"
    case permissionRequired = "PERMISSION REQUIRED"
}

/// Exact permission probe result — do not collapse failures into a single false.
enum PermissionProbe: String {
    case granted = "GRANTED"
    case denied = "DENIED"
    case unavailable = "UNAVAILABLE"
    case unknown = "UNKNOWN"
}
