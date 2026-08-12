// GlaukApp.swift
import SwiftUI
import GlaukCore

@main
struct GlaukApp: App {
    // 本文ウィンドウと設定画面の両方から見るので、ここで持って environmentObject で配る
    @StateObject private var noteIndex = NoteIndex()
    @StateObject private var notesFolder = NotesFolder()
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
        WindowGroup {
            // ★ ナビゲータは DocumentStore と索引を両方持つので、
            //   ContentView の init で組み立てる。ここで渡しておく。
            ContentView(noteIndex: noteIndex, notesFolder: notesFolder)
                .environmentObject(noteIndex)
                .environmentObject(notesFolder)
        }
        // ★ ツリーの開閉はメニューに載せる。ボタンの .keyboardShortcut だけだと、
        //   本文の NSTextView が firstResponder のときに拾われないことがある
        //   (AppKit のビューが先にキーを食べる)。メニューなら必ず届く。
        .commands {
            CommandGroup(after: .sidebar) {
                Button(showTree ? "ノートツリーを隠す" : "ノートツリーを表示") {
                    showTree.toggle()
                }
                .keyboardShortcut("\\", modifiers: .command)
            }
        }

        // ⌘, で開く
        Settings {
            SettingsView()
                .environmentObject(noteIndex)
                .environmentObject(notesFolder)
        }
    }
}
