// NoteTree.swift
import Foundation

/// サイドバーのツリー1行分。`children` が nil のものがノート(開ける葉)。
struct NoteNode: Identifiable, Hashable {
    /// ノートフォルダからの相対パス。フォルダなら末尾に `/` は付けない。
    let id: String
    /// 表示名。ノートは拡張子を落とす。
    let name: String
    let isFolder: Bool
    /// ★ 葉は必ず nil。空配列にすると開閉の三角が出てしまう。
    var children: [NoteNode]?
}

enum NoteTree {
    /// 相対パスの一覧からツリーを組む。フォルダが先、その中は Finder と同じ並び。
    ///
    /// 走査結果は `Programing/PHP/01. Laravel とは.md` のような相対パスの列なので、
    /// 先頭の階層で束ねながら再帰する。深さは Zig 側の MAX_DEPTH で頭打ちになっている。
    nonisolated static func build(from paths: [String], prefix: String = "") -> [NoteNode] {
        var folderPaths: [String: [String]] = [:]
        var folderOrder: [String] = []
        var files: [String] = []

        for path in paths {
            guard let slash = path.firstIndex(of: "/") else {
                files.append(path)
                continue
            }
            let head = String(path[path.startIndex..<slash])
            let rest = String(path[path.index(after: slash)...])
            if folderPaths[head] == nil { folderOrder.append(head) }
            folderPaths[head, default: []].append(rest)
        }

        // localizedStandardCompare は "01, 02, 10" を人間の期待どおりに並べる
        let folders = folderOrder
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
            .map { head in
                NoteNode(id: prefix + head,
                         name: head,
                         isFolder: true,
                         children: build(from: folderPaths[head]!, prefix: prefix + head + "/"))
            }

        let notes = files
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
            .map { file in
                NoteNode(id: prefix + file,
                         name: (file as NSString).deletingPathExtension,
                         isFolder: false,
                         children: nil)
            }

        return folders + notes
    }

    /// 画面に出す1行分。`depth` が字下げの段数。
    struct Row: Identifiable, Equatable {
        let node: NoteNode
        let depth: Int
        var id: String { node.id }
    }

    /// 開いているフォルダの中身だけを平らに並べる
    nonisolated static func rows(_ nodes: [NoteNode],
                                 expanded: Set<String>,
                                 depth: Int = 0) -> [Row] {
        var out: [Row] = []
        for node in nodes {
            out.append(Row(node: node, depth: depth))
            if node.isFolder, expanded.contains(node.id), let children = node.children {
                out.append(contentsOf: rows(children, expanded: expanded, depth: depth + 1))
            }
        }
        return out
    }

    /// `a/b/c.md` → ["a", "a/b"]。開いたノートを見えるようにするために使う。
    nonisolated static func ancestors(of path: String) -> [String] {
        var out: [String] = []
        var prefix = ""
        for part in path.split(separator: "/").dropLast() {
            prefix = prefix.isEmpty ? String(part) : prefix + "/" + part
            out.append(prefix)
        }
        return out
    }

    nonisolated static func allFolders(_ nodes: [NoteNode]) -> Set<String> {
        var out: Set<String> = []
        for node in nodes where node.isFolder {
            out.insert(node.id)
            if let children = node.children { out.formUnion(allFolders(children)) }
        }
        return out
    }
}
