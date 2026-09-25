// Views/SettingsView.swift
import SwiftUI

struct SettingsView: View {
    @ObservedObject var viewModel: DashboardViewModel
    @EnvironmentObject private var appearance: AppearanceStore
    var openAppearance: () -> Void = {}

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: appearance.sectionGap) {
                TerminalPanel(title: "SERVER") {
                    TextField("Server URL", text: $viewModel.serverURL)
                        .font(appearance.font(size: 12, weight: .medium))
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                    MetricRow(label: "Tailscale", value: AppConfig.defaultServerURL, tone: .muted)
                    MetricRow(label: "LAN", value: AppConfig.lanFallbackURL, tone: .muted)
                    ConsoleButton(title: "USE TAILSCALE") { viewModel.serverURL = AppConfig.defaultServerURL }
                    ConsoleButton(title: "USE LAN") { viewModel.serverURL = AppConfig.lanFallbackURL }
                }
                TerminalPanel(title: "AUTHENTICATION") {
                    Toggle("Authentication enabled", isOn: $viewModel.authEnabled)
                        .font(appearance.font(size: 12, weight: .bold))
                        .tint(appearance.accent)
                    SecureField("API token", text: $viewModel.apiToken)
                        .font(appearance.font(size: 12, weight: .medium))
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Text("Token stays in Keychain.")
                        .font(appearance.font(size: 10, weight: .medium))
                        .foregroundStyle(appearance.muted)
                }
                TerminalPanel(title: "HEARTBEAT") {
                    Stepper(value: $viewModel.heartbeatInterval, in: 2...30, step: 1) {
                        Text("Interval \(Int(viewModel.heartbeatInterval)) sec")
                            .font(appearance.font(size: 12, weight: .medium))
                            .foregroundStyle(appearance.text)
                    }
                    .tint(appearance.accent)
                }
                TerminalPanel(title: "DEVICE") {
                    MetricRow(label: "ID", value: viewModel.deviceID, tone: .muted)
                    MetricRow(label: "Name", value: viewModel.deviceName)
                    MetricRow(label: "App", value: "\(AppConfig.appVersion) (\(AppConfig.buildNumber))")
                }
                ConsoleButton(title: "APPEARANCE") { openAppearance() }
                ConsoleButton(title: "SAVE & RECONNECT", prominent: true) {
                    viewModel.saveSettingsAndReconnect()
                }
            }
            .padding(appearance.pad)
            .padding(.bottom, 88)
        }
        .background(appearance.background)
        .navigationTitle("SETTINGS")
        .navigationBarTitleDisplayMode(.inline)
    }
}
