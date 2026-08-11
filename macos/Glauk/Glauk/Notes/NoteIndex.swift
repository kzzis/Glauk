// NoteIndex.swift
import Combine
import Foundation

@MainActor
final class NoteIndex: ObservableObject {
    @Published private(set) var names: [String] = []
    private var pathByName: [String: String] = [:]

    /// ノートフォルダからの相対パス一覧から索引を作る(例: "notes/設計メモ.md")
    func replaceAll(with paths: [String]) {
        var map: [String: String] = [:]
        for path in paths where path.hasSuffix(".md") {
            let name = (path as NSString).deletingPathExtension
            let leaf = (name as NSString).lastPathComponent
            map[leaf] = path
        }
        pathByName = map
        names = map.keys.sorted()
    }

    func loadMock() {
        replaceAll(with: ["AS400アイテムマスタ.md", "IExternalDbGateway.md", "notes/設計メモ.md"])
    }

    func exists(_ name: String) -> Bool { pathByName[name] != nil }
    func path(for name: String) -> String? { pathByName[name] }

    /// 前方一致を先に、部分一致を後に
    func candidates(matching query: String, limit: Int = 20) -> [String] {
        guard !query.isEmpty else { return Array(names.prefix(limit)) }
        let lower = query.lowercased()
        let prefix = names.filter { $0.lowercased().hasPrefix(lower) }
        let contains = names.filter {
            !$0.lowercased().hasPrefix(lower) && $0.lowercased().contains(lower)
        }
        return Array((prefix + contains).prefix(limit))
    }
}
