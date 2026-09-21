import Combine
import Foundation

@MainActor
final class NoteIndex: ObservableObject {
    @Published private(set) var names: [String] = []
    @Published private(set) var isScanning = false
    @Published private(set) var hasFolder = false
    /// 索引の中身が変わるたびに増える。エディタは「リンクの色を塗り直す合図」に使う。
    @Published private(set) var revision = 0
    /// 同名ノートを失わないよう、重複排除前の全パスから組む。
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

    /// フォルダ未設定では判定できないため、リンクを未作成扱いにしない。
    func looksResolvable(_ name: String) -> Bool { !hasFolder || exists(name) }

    /// ノートフォルダからの相対パス
    func path(for name: String) -> String? { pathByName[name] }

    func absolutePath(for name: String, root: String) -> String? {
        guard let rel = pathByName[name] else { return nil }
        return root + "/" + rel
    }

    /// 作成直後のリンク表示を更新するため、走査を待たずに索引へ足す。
    func note(name: String, wasCreatedAt relativePath: String) {
        guard pathByName[name] != relativePath else { return }
        pathByName[name] = relativePath
        names = pathByName.keys.sorted()
        revision += 1
    }

    /// 件数制限なし。名前の前方一致、名前の部分一致、パスの部分一致の順。
    func searchResults(matching query: String) -> [String] {
        rankedMatches(matching: query, includePaths: true)
    }

    /// 補完は名前だけを検索し、表示件数を制限する。
    func candidates(matching query: String, limit: Int = 20) -> [String] {
        Array(rankedMatches(matching: query, includePaths: false).prefix(limit))
    }

    private func rankedMatches(matching query: String, includePaths: Bool) -> [String] {
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
            } else if includePaths, pathByName[name]?.lowercased().contains(lower) == true {
                pathContains.append(name)
            }
        }
        return namePrefix + nameContains + pathContains
    }

    private func depth(of path: String) -> Int {
        path.reduce(0) { $1 == "/" ? $0 + 1 : $0 }
    }
}
