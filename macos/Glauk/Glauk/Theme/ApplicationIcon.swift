import AppKit

@MainActor
enum ApplicationIcon {
    static func update(for preference: ThemePreference = .current) {
        let appearance = preference.appearance ?? NSApp.effectiveAppearance
        let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        let name = isDark ? "GlaukIconDark" : "GlaukIconLight"
        guard let image = NSImage(named: name) else { return }
        NSApp.applicationIconImage = image
    }
}
