// AgentPaneView.swift
import SwiftUI
import SwiftTerm

/// ★ 既にあるインスタンスを返すだけ。SwiftUI が描き直しても
///   同じターミナルが使い回され、対話の途中経過が消えない。
struct AgentPaneView: NSViewRepresentable {
    let controller: AgentPaneController

    func makeNSView(context: Context) -> TerminalView { controller.terminalView }
    func updateNSView(_ nsView: TerminalView, context: Context) {}
}
