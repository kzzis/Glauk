// DocumentStore.swift
import AppKit
import Combine
import UniformTypeIdentifiers

@MainActor
final class DocumentStore: ObservableObject {
    @Published var text: String = "" {
        didSet { if !suppressAutosave { scheduleSave() } }
    }
    @Published private(set) var path: String?
    @Published private(set) var lastError: String?
    /// open() のたびに増える。MarkdownTextView はこれの変化を「差し替え」の合図として使う。
    /// (テキストビューがfirstResponderのままだと通常のbinding経由の更新は無視されるため)
    @Published fileprivate(set) var revision = 0

    fileprivate var saveTask: Task<Void, Never>?
    fileprivate var suppressAutosave = false
    private let debounce: Duration = .milliseconds(800)

    /// 失敗を上部バーに出す。ナビゲータからも使う。
    func report(_ message: String) { lastError = message }

    func open(path newPath: String) {
        guard let contents = GlaukFile.read(path: newPath) else {
            lastError = "開けませんでした: \(newPath)"
            return
        }
        saveTask?.cancel()
        suppressAutosave = true      // 読み込みで保存が走らないように
        path = newPath
        text = contents
        revision += 1
        suppressAutosave = false
    }

    func openWithPanel() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        if let md = UTType(filenameExtension: "md") {
            panel.allowedContentTypes = [md, .plainText]
        }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        open(path: url.path)
    }

    func createWithPanel() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "untitled.md"
        if let md = UTType(filenameExtension: "md") { panel.allowedContentTypes = [md] }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard GlaukFile.write(path: url.path, contents: "") else {
            lastError = "作成できませんでした"
            return
        }
        open(path: url.path)
    }

    private func scheduleSave() {
        guard path != nil else { return }
        saveTask?.cancel()                       // 前の予約を取り消す = デバウンス
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: self?.debounce ?? .milliseconds(800))
            guard !Task.isCancelled, let self else { return }
            await self.saveNow()
        }
    }

    func saveNow() async {
        guard let path, !path.isEmpty else { return }
        let snapshot = text                      // メインスレッドで値をコピー
        let ok = await Task.detached(priority: .utility) {
            GlaukFile.write(path: path, contents: snapshot)   // 別スレッドで書く
        }.value
        if !ok { lastError = "保存に失敗しました" }
    }
}

extension DocumentStore {
    /// 開いているファイルが消えたとき。中身は残さない。
    func close() {
        saveTask?.cancel()
        suppressAutosave = true
        path = nil
        text = ""
        revision += 1
        suppressAutosave = false
    }

    /// 中身はそのままに、書き戻し先だけ付け替える(名前の変更・移動のあと)。
    func rebind(to newPath: String) {
        path = newPath
    }
}

extension DocumentStore {
    struct ReloadResult {
        let oldText: String
        let newText: String
        /// 変わった行の範囲(0始まり)
        let changedLines: Range<Int>
    }

    /// 外から書き換えられたので読み直す。中身が同じなら nil。
    func reloadFromDisk() -> ReloadResult? {
        guard let path, let fresh = GlaukFile.read(path: path) else { return nil }
        guard fresh != text else { return nil }

        let old = text
        let changed = Self.changedLineRange(old: old, new: fresh)

        // ★ リロードで自動保存が走ると、外部の変更を自分が上書きしてしまう
        suppressAutosave = true
        text = fresh
        revision += 1
        suppressAutosave = false

        return ReloadResult(oldText: old, newText: fresh, changedLines: changed)
    }

    /// 前後から一致する行を削っていき、残った範囲を「変わった行」とみなす。
    /// ★ 間に挟まれた無変更行も変更扱いになる。Stage 1 は「どの行が変わったか」
    ///   だけを見るので、ここは割り切る。
    static func changedLineRange(old: String, new: String) -> Range<Int> {
        let oldLines = old.components(separatedBy: "\n")
        let newLines = new.components(separatedBy: "\n")

        var start = 0
        while start < oldLines.count, start < newLines.count,
              oldLines[start] == newLines[start] {
            start += 1
        }

        var oldEnd = oldLines.count
        var newEnd = newLines.count
        while oldEnd > start, newEnd > start,
              oldLines[oldEnd - 1] == newLines[newEnd - 1] {
            oldEnd -= 1
            newEnd -= 1
        }

        return start..<max(start, newEnd)
    }
}
