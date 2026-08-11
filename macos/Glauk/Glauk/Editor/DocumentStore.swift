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
    @Published private(set) var revision = 0

    private var saveTask: Task<Void, Never>?
    private var suppressAutosave = false
    private let debounce: Duration = .milliseconds(800)

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
