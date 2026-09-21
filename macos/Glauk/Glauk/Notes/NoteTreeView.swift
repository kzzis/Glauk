import SwiftUI

enum NoteTreeAction {
    case open(String)                    // 相対パス
    case newNote(inFolder: String)       // 相対パス。ルートは ""
    case newFolder(inFolder: String)
    case rename(String)
    case move(String)
    case trash(String)
    case reveal(String)
}

struct NoteTreeView: View {
    @EnvironmentObject var noteIndex: NoteIndex
    @EnvironmentObject var notesFolder: NotesFolder

    /// いま開いているノートの相対パス(強調表示と自動展開に使う)
    var currentPath: String?
    var onAction: (NoteTreeAction) -> Void

    /// 再走査でツリーが再構築されても開閉状態を保ち、再起動後にも復元する。
    @AppStorage("glauk.expandedFolders") private var expandedRaw = ""
    @State private var expanded: Set<String> = []

    var body: some View {
        VStack(spacing: 0) {
            if !noteIndex.hasFolder {
                empty
            } else {
                header
                if noteIndex.tree.isEmpty {
                    Text(noteIndex.isScanning ? "走査中…" : "ノートがありません")
                        .font(.system(size: 13))
                        .foregroundStyle(ThemeToken.sidebarSecondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    list
                }
            }
        }
        .onAppear { expanded = Set(expandedRaw.split(separator: "\n").map(String.init)) }
        .onChange(of: currentPath) { _, path in reveal(path) }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text("ノート")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(ThemeToken.sidebarSecondary)
            Spacer()
            Menu {
                Button("新規ノート") { onAction(.newNote(inFolder: "")) }
                Button("新規フォルダ") { onAction(.newFolder(inFolder: "")) }
                Divider()
                Button("すべて開く") { expandAll() }
                Button("すべて畳む") { setExpanded([]) }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 15, weight: .medium))
                    .frame(width: 24, height: 26)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .help("ノートの操作")
            Text("\(noteIndex.names.count)")
                .font(.system(size: 11))
                .foregroundStyle(ThemeToken.sidebarSecondary)
                .monospacedDigit()
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 20)
        .frame(height: 32)
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
                .padding(.vertical, 5)
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
        HStack(spacing: 8) {
            if node.isFolder {
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(ThemeToken.sidebarSecondary)
                    .rotationEffect(.degrees(expanded.contains(node.id) ? 90 : 0))
                    .frame(width: 12)
            } else {
                Color.clear.frame(width: 12)
            }
            Image(systemName: node.isFolder ? "folder" : "doc.text")
                .font(.system(size: 13))
                .foregroundStyle(isCurrent ? ThemeToken.ink : ThemeToken.sidebarSecondary)
                .frame(width: 16)
            Text(node.name)
                .lineLimit(1)
                .truncationMode(.middle)
                .foregroundStyle(ThemeToken.ink)
                .font(.system(size: 13))
                .fontWeight(isCurrent ? .semibold : .regular)
            Spacer(minLength: 0)
        }
        .padding(.leading, CGFloat(row.depth) * 13 + 10)
        .padding(.trailing, 8)
        .frame(height: 32)
        .background(isCurrent ? ThemeToken.accent.opacity(0.12) : .clear,
                    in: RoundedRectangle(cornerRadius: 7))
        .padding(.horizontal, 11)
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
        Text("上のボタンからノートフォルダを選択")
            .font(.system(size: 12))
            .foregroundStyle(ThemeToken.sidebarSecondary)
            .multilineTextAlignment(.center)
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

    private func reveal(_ path: String?) {
        guard let path else { return }
        var next = expanded
        next.formUnion(NoteTree.ancestors(of: path))
        guard next != expanded else { return }
        setExpanded(next)
    }
}
