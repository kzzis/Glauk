// NoteFileOps.swift
import AppKit

/// ツリーから触るファイル操作。
///
/// ★ ここだけ Zig ではなく FileManager を使う。「削除」を macOS のゴミ箱へ送る
///   `trashItem` に相当するものが Zig には無く、消す・戻すの意味づけまで含めて
///   OS の作法に乗せたいので、この一群は Swift 側に置く。
///   本文の読み書き(glauk_read_file / glauk_write_file)はこれまでどおり Zig。
enum NoteFileOps {
    struct Failure: Error {
        let message: String
    }

    /// ファイル名に使えない文字を弾く。`/` を通すと意図しない階層ができる。
    static func validate(name: String) throws {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { throw Failure(message: "名前が空です") }
        guard !trimmed.hasPrefix(".") else { throw Failure(message: "`.` で始まる名前は使えません") }
        guard !trimmed.contains("/"), !trimmed.contains(":") else {
            throw Failure(message: "名前に / と : は使えません")
        }
    }

    @discardableResult
    static func createNote(named name: String, in folder: String) throws -> String {
        try validate(name: name)
        let leaf = name.hasSuffix(".md") ? name : name + ".md"
        let path = folder + "/" + leaf
        guard !FileManager.default.fileExists(atPath: path) else {
            throw Failure(message: "同名のファイルが既にあります: \(leaf)")
        }
        let title = (leaf as NSString).deletingPathExtension
        guard GlaukFile.write(path: path, contents: "# \(title)\n\n") else {
            throw Failure(message: "作成できませんでした: \(leaf)")
        }
        return path
    }

    @discardableResult
    static func createFolder(named name: String, in folder: String) throws -> String {
        try validate(name: name)
        let path = folder + "/" + name
        guard !FileManager.default.fileExists(atPath: path) else {
            throw Failure(message: "同名のフォルダが既にあります: \(name)")
        }
        do {
            try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: false)
        } catch {
            throw Failure(message: "作成できませんでした: \(name)")
        }
        return path
    }

    /// 名前を変える。ノートなら `.md` を保つ。新しい絶対パスを返す。
    @discardableResult
    static func rename(_ path: String, to name: String) throws -> String {
        try validate(name: name)
        let isNote = !isDirectory(path) && (path as NSString).pathExtension == "md"
        let leaf = isNote && !name.hasSuffix(".md") ? name + ".md" : name
        let parent = (path as NSString).deletingLastPathComponent
        return try move(path, toDirectory: parent, renamedTo: leaf)
    }

    /// 別のフォルダへ移す。新しい絶対パスを返す。
    @discardableResult
    static func move(_ path: String, toDirectory directory: String,
                     renamedTo newLeaf: String? = nil) throws -> String {
        let leaf = newLeaf ?? (path as NSString).lastPathComponent
        let destination = directory + "/" + leaf
        if destination == path { return path }
        guard !FileManager.default.fileExists(atPath: destination) else {
            throw Failure(message: "移動先に同じ名前があります: \(leaf)")
        }
        // ★ 自分の中へは移せない。folder/a を folder/a/b へ動かすとフォルダごと消える。
        if isDirectory(path), (directory + "/").hasPrefix(path + "/") {
            throw Failure(message: "フォルダを自分の中へは移せません")
        }
        do {
            try FileManager.default.moveItem(atPath: path, toPath: destination)
        } catch {
            throw Failure(message: "移動できませんでした: \(leaf)")
        }
        return destination
    }

    /// macOS のゴミ箱へ送る。Finder から元に戻せる。
    /// ★ App Sandbox でも、ユーザーが選んだフォルダの中のファイルなら通る。
    ///   通らなかったときは理由まで見せる(アクセス権の問題であることが多い)。
    static func trash(_ path: String) throws {
        do {
            try FileManager.default.trashItem(at: URL(fileURLWithPath: path), resultingItemURL: nil)
        } catch {
            let leaf = (path as NSString).lastPathComponent
            throw Failure(message: "ゴミ箱に入れられませんでした: \(leaf) — \(error.localizedDescription)")
        }
    }

    static func revealInFinder(_ path: String) {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
    }

    static func isDirectory(_ path: String) -> Bool {
        var isDir: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: path, isDirectory: &isDir)
        return exists && isDir.boolValue
    }
}
