// GlaukApp.swift
import SwiftUI
import GlaukCore

@main
struct GlaukApp: App {
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
        }
    }
}
