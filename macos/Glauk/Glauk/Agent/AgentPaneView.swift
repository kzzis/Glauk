// AgentPaneView.swift
import SwiftUI
import SwiftTerm

/// ★ 既にあるインスタンスを返すだけ。SwiftUI が描き直しても
///   同じターミナルが使い回され、対話の途中経過が消えない。
struct AgentPaneView: NSViewRepresentable {
    let controller: AgentPaneController

    func makeNSView(context: Context) -> TerminalView {
        // ビュー階層に入った直後にフォーカスを渡す。1周期待たないと window がまだ nil。
        DispatchQueue.main.async { controller.focusTerminal() }
        return controller.terminalView
    }

    /// ★ CGColor に落ちた色は外観の変化に追随しない。SwiftUI がテーマ変更で
    ///   描き直すこのタイミングで入れ直す。
    func updateNSView(_ nsView: TerminalView, context: Context) {
        controller.applyTheme()
    }
}

/// ペインの中身。★ @ObservedObject で受けないと、errorMessage が変わっても
///   画面が描き直されない(@State に持っただけでは購読されない)。
struct AgentPaneBody: View {
    @ObservedObject var controller: AgentPaneController
    @Binding var selectedAgent: Int
    var onSwitch: (AgentKind) -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                // ★ エージェントに渡してあるファイルを常に見せる。入力欄を
                //   差し替えられない場面(既に打ち始めている)でも、どれを指して
                //   いるつもりなのかがここで分かる。
                Image(systemName: "doc.text")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                Text(controller.contextFile ?? "未保存")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.head)
                    .help(controller.contextFile ?? "まだ保存されていないノート")
                Spacer(minLength: 4)
                Picker("", selection: $selectedAgent) {
                    ForEach(AgentKind.allCases) { kind in
                        Text(kind.displayName).tag(Int(kind.rawValue))
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .frame(width: 130)
                .onChange(of: selectedAgent) { _, newValue in
                    // 切り替えは作り直し。同じ会話は引き継げない。
                    onSwitch(AgentKind(rawValue: Int32(newValue)) ?? .claude)
                }
            }
            .padding(.horizontal, 10)
            .frame(height: 28)
            Divider()
            AgentPaneView(controller: controller)
            if let message = controller.errorMessage {
                Divider()
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}
