//
//  ContentView.swift
//  Snaglist
//
//  RootView: the Splash -> Onboarding (first launch only) -> Main app state
//  machine. No login/welcome/auth screens of any kind. iOS 14 safe.
//

import SwiftUI

enum AppPhase { case onboarding, main }

struct RootView: View {

    @StateObject private var store = AppStore()
    @StateObject private var notifications = NotificationManager.shared
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("appearance") private var appearanceRaw = AppAppearance.system.rawValue

    private var appearance: AppAppearance { AppAppearance(rawValue: appearanceRaw) ?? .system }
    
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @State private var phase: AppPhase = .main

    var body: some View {
        ZStack {
            switch phase {
            case .onboarding:
                OnboardingView {
                    hasCompletedOnboarding = true
                    withAnimation(.easeInOut(duration: 0.5)) { phase = .main }
                }
                .transition(.opacity)

            case .main:
                RootTabView()
                    .transition(.opacity)
            }
        }
        .onChange(of: scenePhase) { phase in
            if phase != .active { store.flush() }
        }
        .environmentObject(store)
        .environmentObject(notifications)
        .preferredColorScheme(appearance.colorScheme)
        .onAppear {
            if !hasCompletedOnboarding {
                phase = .onboarding
            } else {
                phase = .main
            }
            configureGlobalAppearance()
        }
    }
    
    /// Clear List/Form table backgrounds (UITableView-backed on iOS 14) so the
    /// inspection backdrop shows through, and make navigation bars transparent.
    private func configureGlobalAppearance() {
        UITableView.appearance().backgroundColor = .clear
        UITableViewCell.appearance().backgroundColor = .clear
        UITextView.appearance().backgroundColor = .clear   // TextEditor backdrop shows the card

        let titleColor = UIColor { $0.userInterfaceStyle == .dark ? UIColor(hex: 0xE8EEF6) : UIColor(hex: 0x0F172A) }
        let nav = UINavigationBarAppearance()
        nav.configureWithTransparentBackground()
        nav.titleTextAttributes = [.foregroundColor: titleColor]
        nav.largeTitleTextAttributes = [.foregroundColor: titleColor]
        UINavigationBar.appearance().standardAppearance = nav
        UINavigationBar.appearance().scrollEdgeAppearance = nav
        UINavigationBar.appearance().compactAppearance = nav
        UINavigationBar.appearance().tintColor = UIColor(hex: 0x2563EB)
    }
    
}
