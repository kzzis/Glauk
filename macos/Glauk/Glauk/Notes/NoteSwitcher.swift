// NoteSwitcher.swift
import SwiftUI

/// ⌘O で出すノート検索。ファイルツリーは作らない(Zenモード単一画面)代わりに、
/// 「出したときだけ出て、Esc で消える」入り口を用意する。
struct NoteSwitcherView: View {
    @EnvironmentObject var noteIndex: NoteIndex
    @EnvironmentObject var notesFolder: NotesFolder

    /// 選ばれたノートの絶対パス
    var onOpen: (String) -> Void
    var onCancel: () -> Void

    @State private var query = ""
    @State private var selection = 0
    @FocusState private var focused: Bool

    private var matches: [String] {
        noteIndex.searchResults(matching: query)
    }

    var body: some View {
        ZStack(alignment: .top) {
            // 背面のクリックで閉じる。ついでに本文を少し沈ませる。
            Color.black.opacity(0.18)
                .ignoresSafeArea()
                .onTapGesture { onCancel() }

            panel
                .frame(width: 520)
                .padding(.top, 90)
        }
    }

    private var panel: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("ノートを検索", text: $query)
                    .textFieldStyle(.plain)
                    .font(.title3)
                    .focused($focused)
                    // ★ キー操作は TextField 自身に付ける。親に付けると、
                    //   フォーカスを持っている TextField が先に食べてしまう。
                    .onKeyPress(.downArrow) { move(by: 1) }
                    .onKeyPress(.upArrow) { move(by: -1) }
                    .onKeyPress(.return) { openSelected() }
                    .onKeyPress(.escape) { onCancel(); return .handled }
                // 全件出ていることが分かるように件数を添える
                if noteIndex.hasFolder {
                    Text(count)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .monospacedDigit()
                }
            }
            .padding(12)

            Divider()

            if !noteIndex.hasFolder {
                message("ノートフォルダが未設定です") {
                    Button("フォルダを選ぶ…") { notesFolder.chooseWithPanel() }
                }
            } else if matches.isEmpty {
                message(query.isEmpty ? "ノートがありません" : "一致するノートがありません") {
                    EmptyView()
                }
            } else {
                results
            }
        }
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.separator))
        .shadow(radius: 24, y: 8)
        // ★ 本文の NSTextView が firstResponder を持っている。同じ描画パスの中で
        //   奪おうとすると取り損ねることがあるので、1ターン待ってから focus する。
        .onAppear { DispatchQueue.main.async { focused = true } }
        .onChange(of: query) { _, _ in selection = 0 }
    }

    private var results: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Array(matches.enumerated()), id: \.element) { i, name in
                        row(name: name, selected: i == selection)
                            .id(i)
                            .contentShape(Rectangle())
                            .onTapGesture { open(name: name) }
                    }
                }
            }
            .frame(maxHeight: 320)
            .onChange(of: selection) { _, new in
                proxy.scrollTo(new, anchor: .center)
            }
        }
    }

    private func row(name: String, selected: Bool) -> some View {
        HStack(spacing: 8) {
            Text(name)
                .lineLimit(1)
            Spacer(minLength: 12)
            // 同名ノートを見分けられるように、どのフォルダのものかを添える
            if let folder = folder(of: name), !folder.isEmpty {
                Text(folder)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.head)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(selected ? Color.accentColor.opacity(0.22) : .clear)
    }

    private func message<Content: View>(
        _ text: String,
        @ViewBuilder trailing: () -> Content
    ) -> some View {
        VStack(spacing: 8) {
            Text(text)
                .font(.callout)
                .foregroundStyle(.secondary)
            trailing()
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }

    private var count: String {
        let hits = matches.count
        let all = noteIndex.names.count
        return hits == all ? "\(all)" : "\(hits) / \(all)"
    }

    private func folder(of name: String) -> String? {
        guard let path = noteIndex.path(for: name) else { return nil }
        let dir = (path as NSString).deletingLastPathComponent
        return dir.isEmpty ? nil : dir
    }

    private func move(by delta: Int) -> KeyPress.Result {
        let list = matches
        guard !list.isEmpty else { return .ignored }
        selection = (selection + delta + list.count) % list.count
        return .handled
    }

    private func openSelected() -> KeyPress.Result {
        let list = matches
        guard list.indices.contains(selection) else { return .ignored }
        open(name: list[selection])
        return .handled
    }

    private func open(name: String) {
        guard let root = notesFolder.root,
              let path = noteIndex.absolutePath(for: name, root: root) else { return }
        onOpen(path)
    }
}
