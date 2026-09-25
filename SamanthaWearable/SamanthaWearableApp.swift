// SamanthaWearableApp.swift
import SwiftUI

@main
struct SamanthaWearableApp: App {
    @StateObject private var dashboard = DashboardViewModel()

    var body: some Scene {
        WindowGroup {
            DashboardView(viewModel: dashboard)
                .preferredColorScheme(.dark)
                .onAppear {
                    dashboard.onAppear()
                }
                .onOpenURL { url in
                    Task {
                        await dashboard.metaGlasses.handleOpenURL(url)
                    }
                }
                .onReceive(NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)) { _ in
                    dashboard.onResignActive()
                }
                .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
                    dashboard.onBecomeActive()
                }
        }
    }
}
