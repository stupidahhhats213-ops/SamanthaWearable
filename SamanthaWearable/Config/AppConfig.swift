// Config/AppConfig.swift
import Foundation

enum AppConfig {
    /// Marketing version and build come from the built Info.plist.
    /// CI sets CURRENT_PROJECT_VERSION to the GitHub Actions run number.
    static var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.2.1"
    }
    static var buildNumber: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "4"
    }

    static let defaultServerURL = "http://100.116.10.96:8510"
    static let lanFallbackURL = "http://192.168.1.241:8510"
    static let defaultHeartbeatInterval: Double = 5.0

    enum Keys {
        static let serverURL = "samantha.serverURL"
        static let authEnabled = "samantha.authEnabled"
        static let heartbeatInterval = "samantha.heartbeatInterval"
        static let deviceID = "samantha.deviceID"
        static let deviceName = "samantha.deviceName"
        static let apiTokenKeychain = "samantha.apiToken"
    }
}
