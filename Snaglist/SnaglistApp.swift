//
//  SnaglistApp.swift
//  Snaglist
//
//  App entry point. Injects the global AppStore + NotificationManager, applies
//  the persisted theme (light/dark/system) and flushes data to disk on
//  backgrounding. iOS 14 safe.
//

import SwiftUI

enum AppAppearance: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }
    var displayName: String { rawValue.capitalized }
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

@main
struct SnaglistApp: App {
    
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegatorapp

    var body: some Scene {
        WindowGroup {
            SplashView()
        }
    }

}
