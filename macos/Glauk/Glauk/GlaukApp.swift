// GlaukApp.swift
import SwiftUI
import GlaukCore

@main
struct GlaukApp: App {
    // 本文ウィンドウと設定画面の両方から見るので、ここで持って environmentObject で配る
    @StateObject private var noteIndex = NoteIndex()
    @StateObject private var notesFolder = NotesFolder()

    init() {
        #if DEBUG
        if glauk_check_leaks() {
            print("[glauk] ⚠️ コア側にメモリリークがあります")
        }
        #endif
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(noteIndex)
                .environmentObject(notesFolder)
        }

        // ⌘, で開く
        Settings {
            SettingsView()
                .environmentObject(noteIndex)
                .environmentObject(notesFolder)
        }
    }
}
