// Views/DashboardView.swift
import SwiftUI

struct DashboardView: View {
    @ObservedObject var viewModel: DashboardViewModel
    @State private var tick = Date()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    header

                    SectionCard(
                        title: "SERVER",
                        trailing: "● \(viewModel.connectionState.rawValue)",
                        trailingColor: statusDotColor(viewModel.connectionState)
                    ) {
                        StatusRow(title: "Host", value: viewModel.hostLabel)
                        StatusRow(title: "URL", value: shortURL(viewModel.serverURL), accent: Color(white: 0.75))
                        StatusRow(
                            title: "Latency",
                            value: viewModel.latencyMs.map { String(format: "%.0f ms", $0) } ?? "N/A"
                        )
                        StatusRow(
                            title: "API",
                            value: viewModel.serverService.map { "\($0) v\(viewModel.serverAPIVersion ?? "?")" } ?? "—"
                        )
                        StatusRow(title: "Device ID", value: shortID(viewModel.deviceID), accent: Color(white: 0.7))
                    }

                    SectionCard(
                        title: "HEARTBEAT",
                        trailing: viewModel.heartbeat.isActive ? "● ACTIVE" : "● IDLE",
                        trailingColor: viewModel.heartbeat.isActive
                            ? Color(red: 0.95, green: 0.54, blue: 0.0)
                            : Color(white: 0.45)
                    ) {
                        StatusRow(title: "Last Send", value: viewModel.lastHeartbeatAgeText)
                        StatusRow(title: "Interval", value: String(format: "%.0f sec", viewModel.heartbeatInterval))
                        StatusRow(title: "Success", value: "\(viewModel.heartbeat.successCount)")
                        StatusRow(title: "Failures", value: "\(viewModel.heartbeat.failureCount)")
                        if let status = viewModel.heartbeat.lastServerStatus {
                            StatusRow(title: "Server", value: status)
                        }
                    }

                    SectionCard(title: "IPHONE") {
                        StatusRow(title: "Name", value: viewModel.deviceName, accent: Color(white: 0.85))
                        StatusRow(title: "Battery", value: viewModel.batteryText)
                        StatusRow(title: "Charging", value: viewModel.chargingText)
                        StatusRow(title: "Network", value: viewModel.networkText)
                    }

                    metaGlassesSection
                    voiceSection

                    if let err = viewModel.lastError
                        ?? viewModel.heartbeat.lastError
                        ?? viewModel.metaGlasses.lastError {
                        Text(err)
                            .font(.system(size: 12, weight: .medium, design: .monospaced))
                            .foregroundStyle(Color(red: 0.89, green: 0.36, blue: 0.20))
                            .padding(.horizontal, 4)
                    }

                    if let test = viewModel.testResult {
                        Text(test)
                            .font(.system(size: 12, weight: .medium, design: .monospaced))
                            .foregroundStyle(Color(white: 0.75))
                            .padding(.horizontal, 4)
                    }

                    Button {
                        viewModel.testConnection()
                    } label: {
                        Text("TEST CONNECTION")
                            .font(.system(size: 13, weight: .bold, design: .monospaced))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Color(red: 0.95, green: 0.54, blue: 0.0))

                    NavigationLink {
                        SettingsView(viewModel: viewModel)
                    } label: {
                        Text("SETTINGS")
                            .font(.system(size: 13, weight: .bold, design: .monospaced))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                    }
                    .buttonStyle(.bordered)
                }
                .padding(16)
            }
            .background(Color(red: 0.035, green: 0.031, blue: 0.024).ignoresSafeArea())
            .navigationBarHidden(true)
            .onReceive(Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()) { now in
                tick = now
            }
            .sheet(isPresented: $viewModel.photoPreviewVisible) {
                photoPreviewSheet
            }
        }
    }

    private var metaGlassesSection: some View {
        let meta = viewModel.metaGlasses
        return SectionCard(
            title: "META GLASSES",
            trailing: "● \(meta.statusText)",
            trailingColor: viewModel.metaTrailingColor
        ) {
            StatusRow(title: "Status", value: meta.connectionState.rawValue)
            StatusRow(title: "Register", value: meta.registrationState.rawValue, accent: Color(white: 0.75))
            StatusRow(title: "Session", value: meta.sessionStateText, accent: Color(white: 0.75))
            StatusRow(
                title: "Device",
                value: meta.connectedDeviceName ?? "—",
                accent: Color(white: 0.85)
            )
            StatusRow(title: "Device ID", value: shortID(meta.connectedDeviceId ?? "—"), accent: Color(white: 0.7))
            StatusRow(title: "Link", value: meta.linkStateText, accent: Color(white: 0.75))
            StatusRow(title: "Compat", value: meta.compatibilityText, accent: Color(white: 0.75))
            StatusRow(title: "Camera", value: "\(meta.cameraLabel.rawValue) · \(meta.cameraPermission.rawValue)")
            StatusRow(title: "Microphone", value: "\(meta.microphoneLabel.rawValue) · \(meta.microphonePermission.rawValue)")
            StatusRow(title: "Audio", value: meta.audioOutputLabel.rawValue)
            StatusRow(title: "Battery", value: viewModel.glassesBatteryText)

            if meta.requiresFirmwareUpdate {
                Text("Firmware update required")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(Color(red: 0.89, green: 0.36, blue: 0.20))
            }

            VStack(spacing: 8) {
                Button {
                    viewModel.connectMetaGlasses()
                } label: {
                    Text(meta.registrationState == .registered ? "CONNECT" : "CONNECT META GLASSES")
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.borderedProminent)
                .tint(Color(red: 0.95, green: 0.54, blue: 0.0))
                .disabled(viewModel.glassesActionBusy || meta.connectionState == .connected || meta.connectionState == .connecting)

                Button {
                    viewModel.disconnectMetaGlasses()
                } label: {
                    Text("DISCONNECT")
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.bordered)
                .disabled(viewModel.glassesActionBusy || !meta.glassesConnected)

                Button {
                    viewModel.testCamera()
                } label: {
                    Text(meta.isCapturingPhoto ? "CAPTURING…" : "TEST CAMERA")
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.bordered)
                .disabled(viewModel.glassesActionBusy || !meta.glassesConnected || meta.isCapturingPhoto)

                if meta.requiresFirmwareUpdate {
                    Button {
                        Task { await meta.openFirmwareUpdate() }
                    } label: {
                        Text("OPEN FIRMWARE UPDATE")
                            .font(.system(size: 12, weight: .bold, design: .monospaced))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                    }
                    .buttonStyle(.bordered)
                }
            }
            .padding(.top, 6)
        }
    }

    private var voiceSection: some View {
        let voice = viewModel.voice
        return SectionCard(title: "VOICE ASSISTANT", trailing: voice.phase.rawValue) {
            StatusRow(title: "Wake phrase", value: "Hey Samantha")
            StatusRow(title: "Wake detection", value: voice.heySamanthaEnabled ? "ENABLED" : "DISABLED")
            StatusRow(title: "Transcript", value: voice.transcript.isEmpty ? "—" : voice.transcript)
            StatusRow(title: "Reply", value: voice.reply.isEmpty ? "—" : voice.reply)
            StatusRow(title: "Audio Route", value: "\(voice.audioRoute) · \(voice.routeDetail)")
            StatusRow(title: "Voice", value: voice.voiceEngine)
            StatusRow(title: "Response", value: voice.responseMode)
            StatusRow(title: "Mood", value: voice.mood)
            StatusRow(title: "LLM", value: voice.llmMs.map { String(format: "%.0f ms", $0) } ?? "—")
            StatusRow(title: "TTS GPU", value: voice.ttsGPU)
            StatusRow(title: "First audio", value: voice.firstAudioMs.map { String(format: "%.0f ms", $0) } ?? "—")
            StatusRow(title: "Synthesis", value: voice.synthesisMs.map { String(format: "%.0f ms", $0) } ?? "—")
            StatusRow(title: "Wake → text", value: voice.wakeToTranscriptMs.map { String(format: "%.0f ms", $0) } ?? "—")
            StatusRow(title: "API", value: voice.apiLatencyMs.map { String(format: "%.0f ms", $0) } ?? "—")
            StatusRow(title: "Total", value: voice.totalLatencyMs.map { String(format: "%.0f ms", $0) } ?? "—")
            Toggle("Hey Samantha", isOn: Binding(
                get: { voice.heySamanthaEnabled },
                set: { voice.heySamanthaEnabled = $0; viewModel.syncVoice() }
            ))
            Toggle("Proactive updates", isOn: Binding(
                get: { voice.proactiveEnabled },
                set: { voice.proactiveEnabled = $0 }
            ))
            Toggle("Mute Samantha", isOn: Binding(
                get: { voice.muted },
                set: { voice.muted = $0 }
            ))
            Button {
                viewModel.voice.toggleTalkFallback()
            } label: {
                Text("TALK")
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.bordered)
            Button {
                viewModel.voice.stopSpeaking()
            } label: {
                Text("STOP SPEAKING")
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.bordered)
            if voice.needsConfirmation {
                Button { viewModel.voice.confirmPending() } label: {
                    Text("CONFIRM")
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.borderedProminent)
                Button { viewModel.voice.cancelPending() } label: {
                    Text("CANCEL")
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.bordered)
            }
        }
    }

    private var photoPreviewSheet: some View {
        NavigationStack {
            VStack(spacing: 16) {
                if let image = viewModel.metaGlasses.lastPhotoImage {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .padding()
                    Text("JPEG \(viewModel.metaGlasses.lastPhotoByteCount) bytes")
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundStyle(Color(white: 0.6))
                } else {
                    Text("No photo")
                        .foregroundStyle(Color(white: 0.5))
                }
                Spacer()
            }
            .background(Color(red: 0.035, green: 0.031, blue: 0.024).ignoresSafeArea())
            .navigationTitle("Camera Capture")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        viewModel.dismissPhotoPreview()
                    }
                }
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("SAMANTHA")
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(Color(red: 0.96, green: 0.92, blue: 0.85))
            Text("WEARABLE BRIDGE  ·  v\(AppConfig.appVersion)")
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundStyle(Color(red: 0.95, green: 0.54, blue: 0.0))
        }
        .padding(.bottom, 4)
        .opacity(tick.timeIntervalSince1970 > 0 ? 1 : 1)
    }

    private func shortURL(_ raw: String) -> String {
        raw.replacingOccurrences(of: "http://", with: "")
    }

    private func shortID(_ raw: String) -> String {
        if raw.count <= 18 { return raw }
        return String(raw.prefix(18)) + "…"
    }
}
