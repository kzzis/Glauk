// NoteNavigator.swift
import AppKit
import Combine

/// ノート間の移動を1か所に集める。
/// タブは作らず履歴だけ持つ(ブラウザと同じ発想)。画面は常に1枚のまま。
@MainActor
final class NoteNavigator: ObservableObject {
    /// `history.last` が今いる場所。1つ前に戻るには removeLast()。
    @Published private(set) var history: [String] = []
    @Published private(set) var forward: [String] = []
    @Published var pendingCreate: PendingCreate?

    struct PendingCreate: Identifiable {
        let id = UUID()
        let name: String
        /// vault からの相対パス。どこに作るかを必ず見せる。
        let relativePath: String
    }

    private let store: DocumentStore
    private let index: NoteIndex
    private let folder: NotesFolder

    init(store: DocumentStore, index: NoteIndex, folder: NotesFolder) {
        self.store = store
        self.index = index
        self.folder = folder
    }

    var canGoBack: Bool { history.count > 1 }
    var canGoForward: Bool { !forward.isEmpty }

    /// いま開いているノートの表示名(拡張子なし)
    var currentName: String? {
        guard let path = store.path else { return nil }
        return ((path as NSString).lastPathComponent as NSString).deletingPathExtension
    }

    /// `[[リンク]]` がクリックされたときの入口
    func follow(link name: String) async {
        guard let root = folder.root else {
            store.report("ノートフォルダが設定されていません(設定 ⌘, から)")
            return
        }
        if let absolute = index.absolutePath(for: name, root: root) {
            await open(at: absolute)
        } else {
            // Obsidian はクリック即作成だが、Glauk は任意フォルダを扱うので確認を挟む
            pendingCreate = PendingCreate(name: name,
                                          relativePath: plannedRelativePath(for: name, root: root))
        }
    }

    /// ツリーやクイックスイッチャーからも通る、唯一の「開く」経路
    func open(at absolutePath: String) async {
        guard absolutePath != store.path else { return }
        // ★ 自動保存は800msデバウンス。打った直後に移動すると未保存のことがある。
        //   「移動したら直前の編集が消えた」を起こさないよう、順序をここで固定する。
        await store.saveNow()
        if let current = store.path, history.last != current { history.append(current) }
        store.open(path: absolutePath)
        if history.last != absolutePath { history.append(absolutePath) }
        forward.removeAll()          // 新しく辿ったら進む先は捨てる
    }

    func goBack() async {
        guard canGoBack else { return }
        await store.saveNow()
        let current = history.removeLast()
        forward.append(current)
        guard let previous = history.last else { return }
        store.open(path: previous)
    }

    func goForward() async {
        guard let next = forward.popLast() else { return }
        await store.saveNow()
        history.append(next)
        store.open(path: next)
    }

    func createAndOpen(name: String) async {
        guard let root = folder.root else { return }
        let relative = plannedRelativePath(for: name, root: root)
        let absolute = root + "/" + relative

        if FileManager.default.fileExists(atPath: absolute) {
            store.report("同名のファイルが既にあります: \(relative)")
            pendingCreate = nil
            return
        }
        guard GlaukFile.write(path: absolute, contents: "# \(name)\n\n") else {
            store.report("作成できませんでした: \(relative)")
            pendingCreate = nil
            return
        }
        // ★ 次の走査を待たずに索引へ足す。待つと、作った直後にもかかわらず
        //   元のノートのリンクが「未作成」の見た目のままになる。
        index.note(name: name, wasCreatedAt: relative)
        await open(at: absolute)
        pendingCreate = nil
    }

    private func plannedRelativePath(for name: String, root: String) -> String {
        let dir = Self.siblingDirectory(of: store.path, under: root)
        return dir.isEmpty ? "\(name).md" : "\(dir)/\(name).md"
    }

    /// 今開いているノートと同じフォルダに作る(ルート直下ではなく手元に置く)。
    /// 状態に依存しない計算なので static にしてある。
    nonisolated static func siblingDirectory(of currentPath: String?, under root: String) -> String {
        guard let currentPath, currentPath.hasPrefix(root + "/") else { return "" }
        let relative = String(currentPath.dropFirst(root.count + 1))
        return (relative as NSString).deletingLastPathComponent
    }
}

extension Notification.Name {
    static let glaukGoBack = Notification.Name("glauk.goBack")
    static let glaukGoForward = Notification.Name("glauk.goForward")
}
