// FileWatcher.swift
import Combine
import Foundation
import GlaukCore

/// 開いているファイルが外から書き換えられたら教える。
/// 監視は Zig の kqueue 側が持ち、こちらは専用スレッドを1本回すだけ。
@MainActor
final class FileWatcher: ObservableObject {
    var onExternalChange: ((String) -> Void)?

    /// ★ 古いスレッドの通知を捨てるための世代番号。
    ///   glauk_watch_next_external_change はブロッキングなので、
    ///   別のノートに移っても前のスレッドはすぐには止まらない。
    ///   「止められないなら、無視できるようにする」。
    private var generation = 0

    func watch(path: String?) {
        generation += 1
        guard let path else { return }

        let myGeneration = generation
        let queue = DispatchQueue(label: "glauk.watch", qos: .utility)
        queue.async { [weak self] in
            while true {
                let changed = path.withCString { glauk_watch_next_external_change($0) }
                guard changed else { break }   // false = 監視できなくなった

                var keepGoing = false
                DispatchQueue.main.sync {
                    guard let self, self.generation == myGeneration else { return }
                    keepGoing = true
                    self.onExternalChange?(path)
                }
                if !keepGoing { break }        // 世代が変わった = もう要らない
            }
        }
    }

    func stop() { generation += 1 }
}
