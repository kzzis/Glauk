// GlaukTheme.swift
import SwiftUI
import AppKit

/// 配色そのもの。ライト/ダークの切り替え(ThemePreference)とは別の軸。
///
/// ★ 実体は Assets.xcassets の名前空間つき Color Set(例: `Paper/InkAccent`)。
///   テーマごとに1組ずつ持たせておけば、どのテーマでもライト/ダークの
///   追随は Asset Catalog 側が面倒を見てくれる。
enum GlaukTheme: String, CaseIterable, Identifiable {
    case paper = "Paper"
    case sumi = "Sumi"
    case ai = "Ai"
    case sepia = "Sepia"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .paper: return "紙とインク"
        case .sumi: return "墨"
        case .ai: return "藍"
        case .sepia: return "古紙"
        }
    }

    var detail: String {
        switch self {
        case .paper: return "朱のインク。既定の配色"
        case .sumi: return "無彩色に寄せた、いちばん静かな配色"
        case .ai: return "藍のインク。青みのある紙"
        case .sepia: return "日に焼けた紙と褐色のインク"
        }
    }

    static let storageKey = "glauk.palette"

    static var current: GlaukTheme {
        GlaukTheme(rawValue: UserDefaults.standard.string(forKey: storageKey) ?? "") ?? .paper
    }

    /// Asset Catalog 上の名前。名前空間つき。
    func name(_ token: String) -> String { "\(rawValue)/\(token)" }
}
