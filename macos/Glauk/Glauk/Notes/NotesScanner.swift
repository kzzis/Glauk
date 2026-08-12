// NotesScanner.swift
import Foundation
import GlaukCore

enum NotesScanner {
    /// root 以下の `.md` を、root からの相対パスで返す。
    /// ★ ディスクI/Oなので Task.detached から呼ぶ。プロジェクト既定が MainActor 隔離なので
    ///   明示的に nonisolated にしておく。
    nonisolated static func scan(root: String) -> [String] {
        var len = 0
        guard let ptr = root.withCString({ glauk_notes_scan($0, &len) }) else { return [] }
        defer { glauk_free_buffer(ptr, len) }   // ★ 取得の直後に解放を予約
        guard len > 0 else { return [] }
        let joined = String(decoding: UnsafeBufferPointer(start: ptr, count: len), as: UTF8.self)
        return joined.split(separator: "\n").map(String.init)
    }
}
