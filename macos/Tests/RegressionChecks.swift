import Foundation

@main
struct RegressionChecks {
    @MainActor
    static func main() throws {
        try checkIndex()
        checkTree()
        try checkDocument()
        print("Swift regression checks passed (search, tree, document lifecycle, external edits)")
    }

    @MainActor
    private static func checkIndex() throws {
        let index = NoteIndex()
        index.replaceAll(with: ["Archive/Apple.md", "Apple.md", "Pineapple.md",
                                "Apple docs/Banana.md", "日本語.md", "ignored.txt"])
        precondition(index.path(for: "Apple") == "Apple.md")
        precondition(index.names == ["Apple", "Banana", "Pineapple", "日本語"])
        precondition(index.searchResults(matching: "APPLE") == ["Apple", "Pineapple", "Banana"])
        precondition(index.candidates(matching: "APPLE") == ["Apple", "Pineapple"])
        precondition(index.candidates(matching: "", limit: 2) == ["Apple", "Banana"])
        precondition(index.candidates(matching: "apple", limit: 0).isEmpty)
        precondition(index.candidates(matching: "日本") == ["日本語"])
        precondition(index.searchResults(matching: "missing").isEmpty)
        let revision = index.revision
        index.replaceAll(with: ["日本語.md", "Apple docs/Banana.md", "Pineapple.md",
                                "Apple.md", "Archive/Apple.md"])
        precondition(index.revision == revision)
        precondition(index.looksResolvable("missing"))
        precondition(index.absolutePath(for: "Apple", root: "/vault") == "/vault/Apple.md")
    }

    private static func checkTree() {
        let tree = NoteTree.build(from: ["z.md", "Folder/10.md", "Folder/2.md",
                                        "Folder/Sub/日本語.md", "a.md"])
        precondition(tree.map(\.id) == ["Folder", "a.md", "z.md"])
        precondition(tree[0].children?.map(\.name) == ["Sub", "2", "10"])
        precondition(tree[1].children == nil)
        precondition(NoteTree.rows(tree, expanded: []).map(\.depth) == [0, 0, 0])
        let rows = NoteTree.rows(tree, expanded: ["Folder", "Folder/Sub"])
        precondition(rows.map(\.depth) == [0, 1, 2, 1, 1, 0, 0])
        precondition(NoteTree.ancestors(of: "Folder/Sub/日本語.md") == ["Folder", "Folder/Sub"])
        precondition(NoteTree.allFolders(tree) == ["Folder", "Folder/Sub"])
    }

    @MainActor
    private static func checkDocument() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("glauk-regression-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("日本語.md")
        let original = "見出し\n本文😀\n末尾\n"
        try original.write(to: file, atomically: true, encoding: .utf8)
        let document = DocumentStore()
        document.open(path: file.path)
        precondition(document.text == original && document.path == file.path)
        precondition(document.revision == 1 && document.lastExternalEdit == nil)
        precondition(document.reloadFromDisk() == nil)

        let updated = "見出し\n更新😀\n追加\n末尾\n"
        try updated.write(to: file, atomically: true, encoding: .utf8)
        let change = document.reloadFromDisk()
        precondition(change?.oldText == original && change?.newText == updated)
        precondition(change?.changedLines == 1..<3)
        precondition(document.lastExternalEdit?.lineDelta == 1)
        precondition(document.lastExternalEdit?.revision == document.revision)
        document.open(path: file.path)
        precondition(document.lastExternalEdit == nil && document.revision == 3)
        document.rebind(to: directory.appendingPathComponent("renamed.md").path)
        precondition(document.text == updated && document.revision == 3)
        document.close()
        precondition(document.path == nil && document.text.isEmpty)
        precondition(document.lastExternalEdit == nil && document.revision == 4)
        precondition(DocumentStore.changedLineRange(old: "a\nb\nc", new: "a\nc") == 1..<1)
        precondition(DocumentStore.changedLineRange(old: "a", new: "a") == 1..<1)
    }
}
