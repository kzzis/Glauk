// NoteTreeView.swift
import SwiftUI

/// ツリーから頼まれた操作。実際に何をするかは ContentView が決める。
/// ★ 確認ダイアログや索引の更新まで View に持たせると、行の描画と混ざって読めなくなる。
enum NoteTreeAction {
    case open(String)                    // 相対パス
    case newNote(inFolder: String)       // 相対パス。ルートは ""
    case newFolder(inFolder: String)
    case rename(String)
    case move(String)
    case trash(String)
    case reveal(String)
}

/// 左のノートツリー。⌘\ で出し入れする。
/// 仕様書の Zen モードを壊さないよう、既定では出るが畳めば元の単一画面に戻る。
struct NoteTreeView: View {
    @EnvironmentObject var noteIndex: NoteIndex
    @EnvironmentObject var notesFolder: NotesFolder

    /// いま開いているノートの相対パス(強調表示と自動展開に使う)
    var currentPath: String?
    /// 相対パスを添えて頼む
    var onAction: (NoteTreeAction) -> Void

    /// ★ 開閉は自分で持つ。List(children:) 任せにすると、
    ///   走査のたびにツリーが作り直されて開いていたフォルダが全部閉じる
    ///   (フォアグラウンド復帰のたびに走査が走るので、実用上かなり困る)。
    ///   改行区切りで覚えておけば再起動しても開いたまま。
    @AppStorage("glauk.expandedFolders") private var expandedRaw = ""
    @State private var expanded: Set<String> = []

    var body: some View {
        VStack(spacing: 0) {
            if !noteIndex.hasFolder {
                empty
            } else if noteIndex.tree.isEmpty {
                Text(noteIndex.isScanning ? "走査中…" : "ノートがありません")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                header
                Divider()
                list
            }
        }
        .onAppear { expanded = Set(expandedRaw.split(separator: "\n").map(String.init)) }
        .onChange(of: currentPath) { _, path in reveal(path) }
    }

    private var header: some View {
        HStack(spacing: 6) {
            Button {
                expandAll()
            } label: {
                Image(systemName: "chevron.down.square")
            }
            .help("すべて開く")

            Button {
                setExpanded([])
            } label: {
                Image(systemName: "chevron.right.square")
            }
            .help("すべて畳む")

            Spacer()
            Menu {
                Button("新規ノート") { onAction(.newNote(inFolder: "")) }
                Button("新規フォルダ") { onAction(.newFolder(inFolder: "")) }
            } label: {
                Image(systemName: "plus")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .frame(width: 22)
            .help("vault の直下に作る")

            Text("\(noteIndex.names.count)")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .monospacedDigit()
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }

    private var list: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(NoteTree.rows(noteIndex.tree, expanded: expanded)) { row in
                        rowView(row)
                            .id(row.id)
                    }
                }
                .padding(.vertical, 4)
            }
            .onChange(of: currentPath) { _, path in
                guard let path else { return }
                // 展開が反映されてからでないと行がまだ存在しない
                DispatchQueue.main.async {
                    withAnimation { proxy.scrollTo(path, anchor: .center) }
                }
            }
        }
    }

    @ViewBuilder
    private func rowView(_ row: NoteTree.Row) -> some View {
        let node = row.node
        let isCurrent = node.id == currentPath
        HStack(spacing: 4) {
            if node.isFolder {
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .rotationEffect(.degrees(expanded.contains(node.id) ? 90 : 0))
                    .frame(width: 10)
            } else {
                // ノートは三角のぶんだけ字下げして、フォルダと縦を揃える
                Color.clear.frame(width: 10)
            }
            Image(systemName: node.isFolder ? "folder" : "doc.text")
                .font(.system(size: 11))
                .foregroundStyle(isCurrent ? Color.accentColor : .secondary)
            Text(node.name)
                .lineLimit(1)
                .truncationMode(.middle)
                .foregroundStyle(isCurrent ? Color.accentColor : Color.primary)
                .fontWeight(isCurrent ? .semibold : .regular)
            Spacer(minLength: 0)
        }
        .padding(.leading, CGFloat(row.depth) * 12 + 8)
        .padding(.trailing, 8)
        .padding(.vertical, 3)
        .background(isCurrent ? Color.accentColor.opacity(0.15) : .clear)
        // ★ 行全体を当たり判定にする。フォルダは名前のどこを押しても開閉する
        //   (三角だけしか反応しないのは狙いにくい)。
        .contentShape(Rectangle())
        .onTapGesture {
            if node.isFolder {
                toggle(node.id)
            } else {
                onAction(.open(node.id))
            }
        }
        .contextMenu { menu(for: node) }
    }

    /// 右クリックのメニュー。フォルダならその中に、ノートなら同じ階層に作る。
    @ViewBuilder
    private func menu(for node: NoteNode) -> some View {
        let container = node.isFolder ? node.id : (node.id as NSString).deletingLastPathComponent
        Button("新規ノート") { onAction(.newNote(inFolder: container)) }
        Button("新規フォルダ") { onAction(.newFolder(inFolder: container)) }
        Divider()
        Button("名前を変更…") { onAction(.rename(node.id)) }
        Button("移動…") { onAction(.move(node.id)) }
        Divider()
        Button("Finder で表示") { onAction(.reveal(node.id)) }
        Button("ゴミ箱に入れる") { onAction(.trash(node.id)) }
    }

    private var empty: some View {
        VStack(spacing: 10) {
            Text("ノートフォルダが未設定です")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("vault を選ぶ…") { notesFolder.chooseWithPanel() }
                .controlSize(.small)
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - 開閉

    private func toggle(_ id: String) {
        var next = expanded
        if next.contains(id) { next.remove(id) } else { next.insert(id) }
        setExpanded(next)
    }

    private func setExpanded(_ next: Set<String>) {
        expanded = next
        expandedRaw = next.sorted().joined(separator: "\n")
    }

    private func expandAll() {
        setExpanded(NoteTree.allFolders(noteIndex.tree))
    }

    /// 開いたノートが深いところにあっても見えるように、親フォルダを開く
    private func reveal(_ path: String?) {
        guard let path else { return }
        var next = expanded
        next.formUnion(NoteTree.ancestors(of: path))
        guard next != expanded else { return }
        setExpanded(next)
    }
}
