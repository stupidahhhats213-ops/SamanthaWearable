// Services/DeviceTelemetry.swift
import Foundation
import UIKit
import Network

@MainActor
final class DeviceTelemetry: ObservableObject {
    @Published private(set) var batteryPercent: Double?
    @Published private(set) var charging: Bool?
    @Published private(set) var networkKind: String = "unknown"

    private var pathMonitor: NWPathMonitor?
    private let monitorQueue = DispatchQueue(label: "samantha.network.monitor")

    func start() {
        UIDevice.current.isBatteryMonitoringEnabled = true
        refreshBattery()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(batteryChanged),
            name: UIDevice.batteryLevelDidChangeNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(batteryChanged),
            name: UIDevice.batteryStateDidChangeNotification,
            object: nil
        )

        let monitor = NWPathMonitor()
        pathMonitor = monitor
        monitor.pathUpdateHandler = { [weak self] path in
            let kind: String
            if path.usesInterfaceType(.wifi) {
                kind = "wifi"
            } else if path.usesInterfaceType(.cellular) {
                kind = "cellular"
            } else if path.status == .satisfied {
                kind = "unknown"
            } else {
                kind = "unknown"
            }
            Task { @MainActor in
                self?.networkKind = kind
            }
        }
        monitor.start(queue: monitorQueue)
    }

    func stop() {
        pathMonitor?.cancel()
        pathMonitor = nil
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func batteryChanged() {
        refreshBattery()
    }

    func refreshBattery() {
        let level = UIDevice.current.batteryLevel
        if level < 0 {
            batteryPercent = nil
        } else {
            batteryPercent = Double(level * 100.0)
        }
        switch UIDevice.current.batteryState {
        case .charging, .full:
            charging = true
        case .unplugged:
            charging = false
        case .unknown:
            charging = nil
        @unknown default:
            charging = nil
        }
    }
}
