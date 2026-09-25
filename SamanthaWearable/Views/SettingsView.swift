// Views/SettingsView.swift
import SwiftUI

struct SettingsView: View {
    @ObservedObject var viewModel: DashboardViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Form {
            Section("Server") {
                TextField("Server URL", text: $viewModel.serverURL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                Text("Default Tailscale: \(AppConfig.defaultServerURL)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text("LAN fallback: \(AppConfig.lanFallbackURL)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Button("Use Tailscale URL") {
                    viewModel.serverURL = AppConfig.defaultServerURL
                }
                Button("Use LAN URL") {
                    viewModel.serverURL = AppConfig.lanFallbackURL
                }
            }

            Section("Authentication") {
                Toggle("Authentication Enabled", isOn: $viewModel.authEnabled)
                SecureField("API Token", text: $viewModel.apiToken)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Text("Token is stored in Keychain and never logged.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Section("Heartbeat") {
                Stepper(
                    value: $viewModel.heartbeatInterval,
                    in: 2...30,
                    step: 1
                ) {
                    Text("Interval: \(Int(viewModel.heartbeatInterval)) sec")
                }
            }

            Section("Device") {
                LabeledContent("Device ID", value: viewModel.deviceID)
                LabeledContent("Name", value: viewModel.deviceName)
                LabeledContent("App", value: "\(AppConfig.appVersion) (\(AppConfig.buildNumber))")
            }

            Section {
                Button("Save & Reconnect") {
                    viewModel.saveSettingsAndReconnect()
                    dismiss()
                }
                .fontWeight(.semibold)
            }
        }
        .scrollContentBackground(.hidden)
        .background(HUD.bg.ignoresSafeArea())
        .tint(HUD.amber)
        .navigationTitle("SETTINGS")
        .navigationBarTitleDisplayMode(.inline)
    }
}
