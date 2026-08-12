// NotesFolder.swift
import AppKit
import Combine

/// ノートフォルダは「任意」。未設定でも Glauk は単一ファイルエディタとして動く。
/// 指定すると `[[` 補完・未作成判定・リンクジャンプが有効になる。
@MainActor
final class NotesFolder: ObservableObject {
    @Published private(set) var root: String?

    private let bookmarkKey = "glauk.notesFolderBookmark"
    private let pathKey = "glauk.notesFolderPath"

    /// startAccessingSecurityScopedResource() を呼んだURL。
    /// 対になる stop を必ず呼べるように持っておく。
    private var accessing: URL?

    init() {
        restoreFromBookmark()
    }

    func chooseWithPanel() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "このフォルダを使う"
        panel.message = "ノートフォルダを選んでください(Obsidian の vault フォルダでも構いません)"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        set(url: url)
    }

    func set(url: URL) {
        stopAccessing()
        root = url.path
        UserDefaults.standard.set(url.path, forKey: pathKey)

        // App Sandbox では「選んだ」という権限はアプリ終了で失われる。
        // ブックマークに焼いておくと、次回起動でダイアログ無しに復元できる。
        if let data = try? url.bookmarkData(options: .withSecurityScope,
                                            includingResourceValuesForKeys: nil,
                                            relativeTo: nil) {
            UserDefaults.standard.set(data, forKey: bookmarkKey)
        } else {
            // ブックマークが作れなくても今回のセッションでは使えるので、続行する
            UserDefaults.standard.removeObject(forKey: bookmarkKey)
        }
    }

    func clear() {
        stopAccessing()
        root = nil
        UserDefaults.standard.removeObject(forKey: pathKey)
        UserDefaults.standard.removeObject(forKey: bookmarkKey)
    }

    /// Obsidian の vault かどうか(移行者向けの表示に使うだけ。機能は変わらない)
    var looksLikeObsidianVault: Bool {
        guard let root else { return false }
        return FileManager.default.fileExists(atPath: root + "/.obsidian")
    }

    private func restoreFromBookmark() {
        guard let data = UserDefaults.standard.data(forKey: bookmarkKey) else {
            // ブックマークが無ければパスだけ復元する(サンドボックスを切って開発する場合)
            root = UserDefaults.standard.string(forKey: pathKey)
            return
        }
        var stale = false
        guard let url = try? URL(resolvingBookmarkData: data,
                                 options: .withSecurityScope,
                                 relativeTo: nil,
                                 bookmarkDataIsStale: &stale) else {
            root = UserDefaults.standard.string(forKey: pathKey)
            return
        }
        if url.startAccessingSecurityScopedResource() { accessing = url }
        root = url.path
        UserDefaults.standard.set(url.path, forKey: pathKey)

        // フォルダを移動・改名されるとブックマークは古くなる。作り直せるうちに作り直す。
        if stale, let fresh = try? url.bookmarkData(options: .withSecurityScope,
                                                    includingResourceValuesForKeys: nil,
                                                    relativeTo: nil) {
            UserDefaults.standard.set(fresh, forKey: bookmarkKey)
        }
    }

    private func stopAccessing() {
        accessing?.stopAccessingSecurityScopedResource()
        accessing = nil
    }
}
