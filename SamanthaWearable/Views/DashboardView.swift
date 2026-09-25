// Views/DashboardView.swift
import SwiftUI

struct DashboardView: View {
    @ObservedObject var viewModel: DashboardViewModel
    @EnvironmentObject private var appearance: AppearanceStore
    @State private var path = NavigationPath()
    @State private var restored = false
    @StateObject private var bubble = SamanthaBubbleModel()

    var body: some View {
        GeometryReader { geo in
            ZStack {
                HStack(spacing: 0) {
                    if geo.size.width > geo.size.height && geo.size.width > 700 {
                        rail
                            .frame(width: 148)
                    }
                    consoleColumn
                }
                .blur(radius: bubble.showsBackdrop ? CGFloat(appearance.blurStrength) * 8 : 0)
                .allowsHitTesting(!bubble.showsBackdrop)
                if bubble.showsBackdrop {
                    Rectangle()
                        .fill(.ultraThinMaterial)
                        .opacity(appearance.blurStrength)
                        .background(Color.black.opacity(0.28 * appearance.blurStrength))
                        .ignoresSafeArea()
                        .allowsHitTesting(false)
                }
            }
            .overlay(alignment: .topLeading) {
                if appearance.bubbleEnabled {
                    BubbleOverlay(
                        model: bubble,
                        container: geo.size,
                        safeTop: geo.safeAreaInsets.top,
                        safeBottom: geo.safeAreaInsets.bottom,
                        safeLeading: geo.safeAreaInsets.leading,
                        safeTrailing: geo.safeAreaInsets.trailing,
                        bottomObstruction: path.isEmpty ? 78 : 12,
                        onAction: handleBubble
                    )
                }
            }
        }
        .background(appearance.background.ignoresSafeArea())
        .tint(appearance.accent)
        .onAppear {
            guard !restored else { return }
            restored = true
            if ProcessInfo.processInfo.arguments.contains("-ui-testing") {
                appearance.setLastPage("home")
                return
            }
            if let route = ConsoleRoute(storage: appearance.lastPage), appearance.lastPage != "home" {
                path.append(route)
            }
        }
        .onChange(of: viewModel.voice.reply) { _, reply in
            viewModel.noteReply(reply)
        }
        .onChange(of: viewModel.connectionState) { _, state in
            viewModel.note("SYSTEM", state.rawValue)
        }
        .onChange(of: viewModel.metaGlasses.connectionState) { _, state in
            viewModel.note("WEARABLE", state.rawValue)
        }
        .sheet(isPresented: $viewModel.photoPreviewVisible) {
            photoPreview
        }
    }

    private var consoleColumn: some View {
        NavigationStack(path: $path) {
            HomeScreen(viewModel: viewModel, open: open)
                .navigationDestination(for: ConsoleRoute.self) { route in
                    destination(route)
                }
        }
    }

    private var rail: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("NAV")
                .font(appearance.font(size: 10, weight: .bold))
                .foregroundStyle(appearance.muted)
                .padding(.bottom, 6)
            railButton("HOME") { path = NavigationPath(); appearance.setLastPage("home") }
            railButton("HERMES") { open(.hermes) }
            railButton("VOICE") { open(.voice) }
            railButton("PROJECTS") { open(.projects) }
            railButton("SYSTEM") { open(.system) }
            railButton("MODELS") { open(.models) }
            railButton("LOGS") { open(.logs) }
            railButton("SETTINGS") { open(.settings) }
            Spacer()
        }
        .padding(10)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(appearance.panel)
        .overlay(alignment: .trailing) {
            Rectangle().fill(appearance.border).frame(width: appearance.lineWidth)
        }
    }

    private func railButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(appearance.font(size: 11, weight: .bold))
                .foregroundStyle(appearance.text)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 6)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func destination(_ route: ConsoleRoute) -> some View {
        switch route {
        case .hermes:
            HermesScreen(viewModel: viewModel)
        case .voice:
            VoiceScreen(viewModel: viewModel)
        case .projects:
            ProjectsScreen(viewModel: viewModel, open: open)
        case .system:
            SystemScreen(viewModel: viewModel, open: open)
        case .models:
            ModelsScreen(viewModel: viewModel)
        case .gpus:
            GPUScreen(viewModel: viewModel)
        case .logs:
            LogsScreen(viewModel: viewModel)
        case .settings:
            SettingsView(viewModel: viewModel, openAppearance: { open(.appearance) })
        case .appearance:
            AppearanceScreen()
        case .wearable:
            WearableScreen(viewModel: viewModel)
        case .project(let id):
            ProjectDetailScreen(viewModel: viewModel, projectID: id)
        }
    }

    private func open(_ route: ConsoleRoute) {
        path.append(route)
        appearance.setLastPage(route.storage)
        closeMenu()
    }

    private func closeMenu() {
        bubble.dismiss()
    }

    private func handleBubble(_ action: String) {
        switch action {
        case "hermes.open":
            open(.hermes)
        case "hermes.status":
            viewModel.commandTarget = "HERMES"
            viewModel.submitConsole("status")
            closeMenu()
        case "hermes.interrupt":
            viewModel.interruptHermes()
            closeMenu()
        case "hermes.reconnect":
            viewModel.reconnectEvents()
            closeMenu()
        case "hermes.restart":
            viewModel.commandTarget = "HERMES"
            viewModel.submitConsole("restart")
            closeMenu()
        case "hermes.logs":
            appearance.setLogFilter("HERMES")
            open(.logs)
        case "voice.wake":
            viewModel.voice.heySamanthaEnabled.toggle()
            viewModel.syncVoice()
        case "voice.mute":
            viewModel.voice.muted.toggle()
        case "voice.stop":
            viewModel.voice.stopSpeaking()
            closeMenu()
        case "voice.route", "voice.page", "voice.follow", "voice.tts":
            open(.voice)
        case "system.gpus":
            open(.gpus)
        case "system.models":
            open(.models)
        case "system.services", "system.network", "system.storage":
            open(.system)
        case "system.health":
            viewModel.testConnection()
            closeMenu()
        case "system.wearable":
            open(.wearable)
        case "projects.open":
            if let id = viewModel.projects.first?.id {
                appearance.setSelectedProject(appearance.selectedProject.isEmpty ? id : appearance.selectedProject)
                open(.project(appearance.selectedProject))
            } else {
                open(.projects)
            }
        case "projects.builds", "projects.git", "projects.switch":
            open(.projects)
        case "logs.open":
            open(.logs)
        case "settings.open":
            open(.settings)
        case "settings.appearance":
            open(.appearance)
        default:
            break
        }
    }

    private var photoPreview: some View {
        NavigationStack {
            VStack(spacing: 16) {
                if let image = viewModel.metaGlasses.lastPhotoImage {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .padding()
                    Text("JPEG \(viewModel.metaGlasses.lastPhotoByteCount) bytes")
                        .font(appearance.font(size: 12, weight: .medium))
                        .foregroundStyle(appearance.muted)
                } else {
                    Text("No photo")
                        .foregroundStyle(appearance.muted)
                }
                Spacer()
            }
            .background(appearance.background.ignoresSafeArea())
            .navigationTitle("Camera Capture")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { viewModel.dismissPhotoPreview() }
                }
            }
        }
    }
}
