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
        /// ★ 再描画を頼む相手。layoutManager.invalidateDisplay だけでは
        ///   画面が更新されないことがある(下の tick を参照)。
        weak var textView: NSTextView?
        let range: NSRange
        let color: NSColor
        let startedAt: CFAbsoluteTime
    }

    var duration: TimeInterval = 4.0
    /// にじみ始めてから一番濃くなるまで。★ duration に対する割合ではなく秒で持つ。
    ///   全体を伸ばしたときに立ち上がりまで間延びすると、インクが染みる感じが消える。
    var riseDuration: TimeInterval = 0.3
    /// 文字が読めなくならない上限。これ以上濃くすると演出が邪魔になる。
    var peakAlpha: CGFloat = 0.14
    private let frameInterval: TimeInterval = 1.0 / 30.0

    private var blooms: [Bloom] = []
    private var timer: Timer?
    #if DEBUG
    private var loggedFirstTick = false
    #endif

    func bloom(range: NSRange, in layoutManager: NSLayoutManager,
               color: NSColor, textView: NSTextView?) {
        guard range.length > 0 else { return }
        // 同じ場所のにじみが残っていると濃さが二重になる。新しい方だけ残す。
        blooms.removeAll { $0.layoutManager === layoutManager && $0.range == range }
        blooms.append(Bloom(layoutManager: layoutManager, textView: textView, range: range,
                            color: color, startedAt: CFAbsoluteTimeGetCurrent()))
        #if DEBUG
        loggedFirstTick = false
        print("[nijimi] bloom 受付 \(range) / 本文 \(layoutManager.textStorage?.length ?? -1)")
        #endif
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
            guard let lm = bloom.layoutManager else {
                #if DEBUG
                print("[nijimi] layoutManager が消えていた")
                #endif
                continue
            }
            // 本文が縮んで範囲が外に出ることがある。触る前に必ず丸める。
            let length = lm.textStorage?.length ?? 0
            let range = bloom.range.clamped(to: length)
            guard range.length > 0 else {
                #if DEBUG
                print("[nijimi] 範囲が空になった (元 \(bloom.range) / 本文 \(length))")
                #endif
                continue
            }

            let progress = min(1.0, (now - bloom.startedAt) / duration)
            if progress >= 1.0 {
                lm.removeTemporaryAttribute(.backgroundColor, forCharacterRange: range)
                redraw(bloom, range: range, in: lm)   // 消えたことも描き直さないと残る
                #if DEBUG
                print("[nijimi] 乾いた \(range)")
                #endif
                continue
            }
            let alpha = alphaCurve(progress) * peakAlpha
            lm.addTemporaryAttributes([.backgroundColor: bloom.color.withAlphaComponent(alpha)],
                                      forCharacterRange: range)
            // ★ ここが要。addTemporaryAttributes も invalidateDisplay も、
            //   「そのレイアウトが既に生成されている」ことを前提に再描画を予約する。
            //   本文を丸ごと差し替えた直後はまだ生成されておらず、予約が捨てられる。
            //   実測でも、一時属性は 2.4 秒ちゃんと乗っているのに一度も描き直されず、
            //   画面には何も出なかった。テキストビューに直接頼めば必ず描き直される。
            lm.invalidateDisplay(forCharacterRange: range)
            redraw(bloom, range: range, in: lm)
            #if DEBUG
            if !loggedFirstTick {
                loggedFirstTick = true
                print(String(format: "[nijimi] 最初のtick alpha=%.3f 範囲=%@ 色=%@",
                             alpha, NSStringFromRange(range), bloom.color.description))
            }
            #endif
            stillRunning.append(bloom)
        }

        blooms = stillRunning
        // ★ 仕事が無いのに 30fps で回り続けるとバッテリーを食う
        if blooms.isEmpty {
            timer?.invalidate()
            timer = nil
        }
    }

    /// にじんでいる行だけを描き直させる。取れなければビュー全体に頼む。
    private func redraw(_ bloom: Bloom, range: NSRange, in lm: NSLayoutManager) {
        guard let textView = bloom.textView else { return }
        guard let container = lm.textContainers.first else {
            textView.needsDisplay = true
            return
        }
        let glyphs = lm.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
        var rect = lm.boundingRect(forGlyphRange: glyphs, in: container)
        guard !rect.isEmpty else {
            textView.needsDisplay = true
            return
        }
        rect.origin.x += textView.textContainerInset.width
        rect.origin.y += textView.textContainerInset.height
        // 行間ぶん少し広げる。境目に描き残しが出ないように。
        textView.setNeedsDisplay(rect.insetBy(dx: -4, dy: -4))
    }

    /// 素早くにじみ、ゆっくり乾く。
    /// ★ 減衰を線形にすると、ただの点滅に見える。
    private func alphaCurve(_ p: Double) -> CGFloat {
        let riseUntil = min(0.5, riseDuration / duration)
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
