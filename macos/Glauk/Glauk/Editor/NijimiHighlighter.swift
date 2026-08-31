// NijimiHighlighter.swift
import AppKit

/// 外から書き換えられた行に、インクがにじんで乾くような色を重ねる。
///
/// ★ NSTextStorage ではなく NSLayoutManager の「一時属性」を使う。
///   実属性に貼ると Undo 履歴がにじみで埋まり、textDidChange まで飛んで
///   自動保存が誘発される。見た目だけの演出は一時属性が正解。
@MainActor
final class NijimiHighlighter {
    /// 進行中のにじみ1件
    private struct Bloom {
        /// ★ ノートを切り替えると layoutManager は作り直される。
        ///   弱参照にしておけば、消えた後は静かに捨てられる。
        weak var layoutManager: NSLayoutManager?
        let range: NSRange
        let color: NSColor
        let startedAt: CFAbsoluteTime
    }

    var duration: TimeInterval = 2.4
    /// 文字が読めなくならない上限。これ以上濃くすると演出が邪魔になる。
    var peakAlpha: CGFloat = 0.14
    private let frameInterval: TimeInterval = 1.0 / 30.0

    private var blooms: [Bloom] = []
    private var timer: Timer?

    func bloom(range: NSRange, in layoutManager: NSLayoutManager, color: NSColor) {
        guard range.length > 0 else { return }
        // 同じ場所のにじみが残っていると濃さが二重になる。新しい方だけ残す。
        blooms.removeAll { $0.layoutManager === layoutManager && $0.range == range }
        blooms.append(Bloom(layoutManager: layoutManager, range: range,
                            color: color, startedAt: CFAbsoluteTimeGetCurrent()))
        startTimerIfNeeded()
    }

    private func startTimerIfNeeded() {
        guard timer == nil else { return }
        // ★ Timer.scheduledTimer は .default モードで登録され、スクロール中や
        //   メニュー操作中に止まる。.common で入れ直すと止まらない。
        let t = Timer(timeInterval: frameInterval, repeats: true) { [weak self] _ in
            // Timer のクロージャは @Sendable 扱いだが、実際にはメインRunLoopから呼ばれる
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func tick() {
        let now = CFAbsoluteTimeGetCurrent()
        var stillRunning: [Bloom] = []

        for bloom in blooms {
            guard let lm = bloom.layoutManager else { continue }   // 消えていたら捨てる
            // 本文が縮んで範囲が外に出ることがある。触る前に必ず丸める。
            let length = lm.textStorage?.length ?? 0
            let range = bloom.range.clamped(to: length)
            guard range.length > 0 else { continue }

            let progress = min(1.0, (now - bloom.startedAt) / duration)
            if progress >= 1.0 {
                lm.removeTemporaryAttribute(.backgroundColor, forCharacterRange: range)
                continue
            }
            let alpha = alphaCurve(progress) * peakAlpha
            lm.addTemporaryAttributes([.backgroundColor: bloom.color.withAlphaComponent(alpha)],
                                      forCharacterRange: range)
            stillRunning.append(bloom)
        }

        blooms = stillRunning
        // ★ 仕事が無いのに 30fps で回り続けるとバッテリーを食う
        if blooms.isEmpty {
            timer?.invalidate()
            timer = nil
        }
    }

    /// 素早くにじみ、ゆっくり乾く。
    /// ★ 減衰を線形にすると、ただの点滅に見える。
    private func alphaCurve(_ p: Double) -> CGFloat {
        let riseUntil = 0.12          // 全体 2.4 秒のうち約 0.3 秒で立ち上がる
        if p < riseUntil { return CGFloat(p / riseUntil) }
        let dry = (p - riseUntil) / (1 - riseUntil)
        return CGFloat(pow(1 - dry, 1.6))
    }

    /// 別のノートを開いたときなど、残っているにじみを全部消す。
    /// ★ テキストビューは使い回されるので、消さないと前のノートのにじみが
    ///   新しいノートの同じ文字位置に残る。
    func cancelAll(in layoutManager: NSLayoutManager) {
        timer?.invalidate()
        timer = nil
        blooms.removeAll()
        let length = layoutManager.textStorage?.length ?? 0
        guard length > 0 else { return }
        layoutManager.removeTemporaryAttribute(.backgroundColor,
                                               forCharacterRange: NSRange(location: 0, length: length))
    }
}
