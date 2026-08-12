// NoteIndex.swift
import Combine
import Foundation

@MainActor
final class NoteIndex: ObservableObject {
    @Published private(set) var names: [String] = []
    @Published private(set) var isScanning = false
    /// ノートフォルダが設定されているか
    @Published private(set) var hasFolder = false
    /// 索引の中身が変わるたびに増える。エディタは「リンクの色を塗り直す合図」に使う。
    @Published private(set) var revision = 0
    /// サイドバー用のツリー。★ 同名で潰れる前の「全パス」から組む。
    ///   names は同名を1つに寄せてあるので、そのまま使うとノートが消える。
    @Published private(set) var tree: [NoteNode] = []
    private var pathByName: [String: String] = [:]
    private var allPaths: [String] = []

    /// ノートフォルダからの相対パス一覧から索引を作る(例: "notes/設計メモ.md")
    func replaceAll(with paths: [String]) {
        let sorted = paths.filter { $0.hasSuffix(".md") }.sorted()
        var map: [String: String] = [:]
        for path in sorted {
            let noExt = (path as NSString).deletingPathExtension
            let leaf = (noExt as NSString).lastPathComponent
            // 同名ノートは階層が浅い方を採用する(Obsidian の曖昧リンクの挙動に近い)
            if let existing = map[leaf], depth(of: existing) <= depth(of: path) { continue }
            map[leaf] = path
        }
        // 中身が同じなら塗り直しの合図も出さない
        guard map != pathByName || sorted != allPaths else { return }
        pathByName = map
        allPaths = sorted
        names = map.keys.sorted()
        tree = NoteTree.build(from: sorted)
        revision += 1
    }

    /// フォルダを走査して索引を作り直す。未設定なら空にする。
    func refresh(root: String?) async {
        hasFolder = root != nil
        guard let root else { replaceAll(with: []); return }
        isScanning = true
        defer { isScanning = false }

        #if DEBUG
        let t0 = CFAbsoluteTimeGetCurrent()
        #endif
        // 走査はディスクI/Oなので別スレッドへ逃がす。大きな vault でもUIは止まらない。
        let paths = await Task.detached(priority: .utility) {
            NotesScanner.scan(root: root)
        }.value
        #if DEBUG
        let ms = (CFAbsoluteTimeGetCurrent() - t0) * 1000
        print("[scan] \(paths.count) notes in \(String(format: "%.0f", ms))ms")
        #endif

        replaceAll(with: paths)
    }

    func exists(_ name: String) -> Bool { pathByName[name] != nil }

    /// 未作成ノートの区別表示に使う。
    /// ★ フォルダ未設定のときは判定材料が無い。ここで false を返すと本文中の
    ///   `[[リンク]]` が全部グレーの点線になってしまうので、「ある」ものとして扱う。
    func looksResolvable(_ name: String) -> Bool { !hasFolder || exists(name) }

    /// ノートフォルダからの相対パス
    func path(for name: String) -> String? { pathByName[name] }

    func absolutePath(for name: String, root: String) -> String? {
        guard let rel = pathByName[name] else { return nil }
        return root + "/" + rel
    }

    /// Step 5b の新規作成で、走査を待たずに索引へ足す
    func note(name: String, wasCreatedAt relativePath: String) {
        guard pathByName[name] != relativePath else { return }
        pathByName[name] = relativePath
        names = pathByName.keys.sorted()
        revision += 1
    }

    /// クイックスイッチャー用。★ 件数を絞らない。
    /// `candidates` は補完ポップアップ用に上限があるので、そのまま使うと
    /// 「全部出てこない」ことになる。並びは
    /// 名前の前方一致 → 名前の部分一致 → パスの部分一致 の順。
    func searchResults(matching query: String) -> [String] {
        guard !query.isEmpty else { return names }
        let lower = query.lowercased()
        var namePrefix: [String] = []
        var nameContains: [String] = []
        var pathContains: [String] = []
        for name in names {
            let lowered = name.lowercased()
            if lowered.hasPrefix(lower) {
                namePrefix.append(name)
            } else if lowered.contains(lower) {
                nameContains.append(name)
            } else if pathByName[name]?.lowercased().contains(lower) == true {
                // フォルダ名でも辿れるようにする(例: "Laravel" で資料フォルダ配下が出る)
                pathContains.append(name)
            }
        }
        return namePrefix + nameContains + pathContains
    }

    /// `[[` 補完のポップアップ用。前方一致を先に、部分一致を後に
    func candidates(matching query: String, limit: Int = 20) -> [String] {
        guard !query.isEmpty else { return Array(names.prefix(limit)) }
        let lower = query.lowercased()
        let prefix = names.filter { $0.lowercased().hasPrefix(lower) }
        let contains = names.filter {
            !$0.lowercased().hasPrefix(lower) && $0.lowercased().contains(lower)
        }
        return Array((prefix + contains).prefix(limit))
    }

    private func depth(of path: String) -> Int {
        path.reduce(0) { $1 == "/" ? $0 + 1 : $0 }
    }
}
