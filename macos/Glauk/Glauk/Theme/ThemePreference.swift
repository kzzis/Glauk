// ThemePreference.swift
import SwiftUI
import AppKit

/// OS 追従か、手動で固定するか。
enum ThemePreference: String, CaseIterable, Identifiable {
    case auto, light, dark

    var id: String { rawValue }

    var label: String {
        switch self {
        case .auto: return "システムに合わせる"
        case .light: return "紙"
        case .dark: return "夜"
        }
    }

    /// nil = OS 追従
    var colorScheme: ColorScheme? {
        switch self {
        case .auto: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }

    var appearance: NSAppearance? {
        switch self {
        case .auto: return nil
        case .light: return NSAppearance(named: .aqua)
        case .dark: return NSAppearance(named: .darkAqua)
        }
    }

    static let storageKey = "glauk.theme"

    static var current: ThemePreference {
        ThemePreference(rawValue: UserDefaults.standard.string(forKey: storageKey) ?? "") ?? .auto
    }

    /// ★ `.preferredColorScheme` は SwiftUI の階層にしか効かない。
    ///   自前で持っている NSWindow にも同じ設定を入れないと、
    ///   タイトルバーだけ色が違う、という状態になる。
    static func apply(_ preference: ThemePreference, to window: NSWindow?) {
        window?.appearance = preference.appearance
        // メニューバーの項目や設定ウィンドウなど、アプリ全体も揃える
        NSApp.appearance = preference.appearance
    }
}
