// Services/DeviceIdentity.swift
import Foundation
import UIKit

enum DeviceIdentity {
    static var deviceID: String {
        if let existing = UserDefaults.standard.string(forKey: AppConfig.Keys.deviceID),
           !existing.isEmpty {
            return existing
        }
        let created = "iphone-\(UUID().uuidString.lowercased())"
        UserDefaults.standard.set(created, forKey: AppConfig.Keys.deviceID)
        return created
    }

    static var deviceName: String {
        if let stored = UserDefaults.standard.string(forKey: AppConfig.Keys.deviceName),
           !stored.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return stored
        }
        let name = UIDevice.current.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolved = name.isEmpty ? "iPhone" : name
        UserDefaults.standard.set(resolved, forKey: AppConfig.Keys.deviceName)
        return resolved
    }

    static func registrationPayload(appVersion: String = AppConfig.appVersion) -> DeviceRegistration {
        DeviceRegistration(
            deviceId: deviceID,
            deviceName: deviceName,
            deviceType: "iphone",
            platform: "ios",
            appVersion: appVersion,
            glassesConnected: false,
            glassesName: nil,
            capabilities: []
        )
    }
}
