// Config/AppConfig.swift
import Foundation

enum AppConfig {
    static let appVersion = "0.2.0"
    static let buildNumber = "3"

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
