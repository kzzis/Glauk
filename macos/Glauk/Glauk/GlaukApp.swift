// GlaukApp.swift
import SwiftUI
import GlaukCore

@main
struct GlaukApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    /// ★ ContentView と同じキーを見る。UserDefaults 越しなので、
    ///   メニューから切り替えても本文側の @AppStorage がそのまま追従する。
    @AppStorage("glauk.showTree") private var showTree = true

    init() {
        #if DEBUG
        if glauk_check_leaks() {
            print("[glauk] ⚠️ コア側にメモリリークがあります")
        }
        #endif
    }

    var body: some Scene {
        // ★ 本文のウィンドウは AppDelegate が持つので WindowGroup は置かない。
        //   App プロトコルは Scene を最低1つ要求するので、Settings を置く。
        //   「⌘, で設定が開く」が副産物として付いてくる。
        Settings {
            SettingsView()
                .environmentObject(appDelegate.noteIndex)
                .environmentObject(appDelegate.notesFolder)
        }
        // ★ ツリーの開閉はメニューに載せる。ボタンの .keyboardShortcut だけだと、
        //   本文の NSTextView が firstResponder のときに拾われないことがある
        //   (AppKit のビューが先にキーを食べる)。メニューなら必ず届く。
        .commands {
            // WindowGroup を外すと File メニューごと消えるので、自分で並べ直す
            CommandGroup(replacing: .newItem) {
                Button("新規…") { NotificationCenter.default.post(name: .glaukNewFile, object: nil) }
                Button("ノートを探す…") { NotificationCenter.default.post(name: .glaukFindNote, object: nil) }
                    .keyboardShortcut("o", modifiers: .command)
                Button("開く…") { NotificationCenter.default.post(name: .glaukOpenFile, object: nil) }
                    .keyboardShortcut("o", modifiers: [.command, .shift])
            }
            CommandGroup(after: .sidebar) {
                Button(showTree ? "ノートツリーを隠す" : "ノートツリーを表示") {
                    showTree.toggle()
                }
                .keyboardShortcut("\\", modifiers: .command)
                Button("AIペインを出し入れ") {
                    NotificationCenter.default.post(name: .glaukToggleAgent, object: nil)
                }
                .keyboardShortcut("j", modifiers: .command)
            }
        }
    }
}
