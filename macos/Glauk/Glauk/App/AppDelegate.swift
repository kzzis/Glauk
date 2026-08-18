// AppDelegate.swift
import AppKit
import SwiftUI

/// ウィンドウを自分で1つ持ち続ける。SwiftUI の WindowGroup は使わない。
///
/// ★ WindowGroup だと、閉じたときに SwiftUI がインスタンスを捨ててしまう。
///   ⌥Space から数十msで出したいので、作り直さずに show/hide で切り替える。
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let overlay = OverlayWindowController()
    private let hotKey = HotKeyCenter()
    let noteIndex = NoteIndex()
    let notesFolder = NotesFolder()
    private var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        overlay.build(
            rootView: ContentView(noteIndex: noteIndex, notesFolder: notesFolder)
                .environmentObject(noteIndex)
                .environmentObject(notesFolder)
        )
        installStatusItem()

        hotKey.onTrigger = { [weak self] in self?.overlay.toggle() }
        hotKey.register()

        overlay.show()
    }

    /// Dock アイコンをクリックしたとき
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        if !hasVisibleWindows { overlay.show() }
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        hotKey.unregister()
    }

    // MARK: - メニューバー

    private func installStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "eye", accessibilityDescription: "Glauk")

        let menu = NSMenu()
        let open = NSMenuItem(title: "Glauk を開く (⌥Space)",
                              action: #selector(openFromMenu), keyEquivalent: "")
        open.target = self          // ★ これが無いと項目がグレーアウトして押せない
        menu.addItem(open)
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "終了", action: #selector(quitApp), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
        item.menu = menu
        statusItem = item
    }

    @objc private func openFromMenu() { overlay.show() }
    @objc private func quitApp() { NSApp.terminate(nil) }
}
