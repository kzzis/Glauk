// アプリアイコンを作る。
//   swiftc -parse-as-library make-app-icon.swift -o makeicon
//   ./makeicon app-icon-source.png <出力フォルダ> [outline|silhouette]
import AppKit

@main
struct MakeIcon {
    /// macOS の角丸(スーパー楕円)。roundedRect の円弧だと角が丸すぎて
    /// 他のアプリのアイコンと形が揃わない。
    static func squircle(in rect: NSRect, n: Double = 5) -> NSBezierPath {
        let path = NSBezierPath()
        let a = rect.width / 2, b = rect.height / 2
        let cx = rect.midX, cy = rect.midY
        let steps = 720
        for i in 0...steps {
            let t = Double(i) / Double(steps) * 2 * .pi
            let ct = cos(t), st = sin(t)
            let x = a * (ct < 0 ? -1 : 1) * pow(abs(ct), 2 / n)
            let y = b * (st < 0 ? -1 : 1) * pow(abs(st), 2 / n)
            let p = NSPoint(x: cx + x, y: cy + y)
            if i == 0 { path.move(to: p) } else { path.line(to: p) }
        }
        path.close()
        return path
    }

    @MainActor static func main() {
        let args = ProcessInfo.processInfo.arguments
        let srcPath = args[1]
        let outDir = args[2]
        let style = args.count > 3 ? args[3] : "silhouette"

        guard let src = NSImage(contentsOfFile: srcPath),
              let srcRep = NSBitmapImageRep(data: src.tiffRepresentation!) else {
            print("読み込めない"); exit(1)
        }
        let w = srcRep.pixelsWide, h = srcRep.pixelsHigh

        // --- 背景色と、画素ごとの「濃さ」を取る ---
        let bg = srcRep.colorAt(x: 2, y: 2)!.usingColorSpace(.sRGB)!
        let bgB = bg.brightnessComponent
        let span = Swift.max(bgB - 0.06, 0.01)
        var darkness = [Float](repeating: 0, count: w * h)   // 0=背景 1=真っ黒
        for y in 0..<h {
            for x in 0..<w {
                let b = srcRep.colorAt(x: x, y: y)?.usingColorSpace(.sRGB)?.brightnessComponent ?? bgB
                darkness[y * w + x] = Float(Swift.max(0, Swift.min(1, (bgB - b) / span)))
            }
        }

        // --- 線の外接矩形 ---
        var minX = w, minY = h, maxX = 0, maxY = 0
        for y in 0..<h {
            for x in 0..<w where darkness[y * w + x] > 0.35 {
                minX = Swift.min(minX, x); maxX = Swift.max(maxX, x)
                minY = Swift.min(minY, y); maxY = Swift.max(maxY, y)
            }
        }
        guard minX < maxX else { print("線が見つからない"); exit(1) }
        let ink = NSRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
        print("画像 \(w)x\(h)  背景 \(hex(bg))  線の範囲 \(ink)  形式 \(style)")

        let alpha = style == "silhouette"
            ? silhouette(darkness: darkness, w: w, h: h)
            : darkness.map { UInt8($0 * 255) }

        let stroke = image(alpha: alpha, w: w, h: h, bounds: ink)

        // --- 1024 のマスターを描く ---
        let canvas: CGFloat = 1024
        // Big Sur 以降の慣習: 1024 のうち中身は 824 角
        let plate = NSRect(x: 100, y: 100, width: 824, height: 824)
        let master = NSImage(size: NSSize(width: canvas, height: canvas))
        master.lockFocus()
        NSColor.clear.set()
        NSRect(x: 0, y: 0, width: canvas, height: canvas).fill()
        bg.setFill()
        squircle(in: plate).fill()

        let inset: CGFloat = 46
        let box = plate.insetBy(dx: inset, dy: inset)
        let scale = Swift.min(box.width / ink.width, box.height / ink.height)
        let drawn = NSRect(x: box.midX - ink.width * scale / 2,
                           y: box.midY - ink.height * scale / 2,
                           width: ink.width * scale,
                           height: ink.height * scale)
        NSGraphicsContext.current?.imageInterpolation = .high
        stroke.draw(in: drawn, from: .zero, operation: .sourceOver, fraction: 1)
        master.unlockFocus()

        // --- 書き出し ---
        let sizes: [(Int, String)] = [
            (16, "icon_16x16"), (32, "icon_16x16@2x"),
            (32, "icon_32x32"), (64, "icon_32x32@2x"),
            (128, "icon_128x128"), (256, "icon_128x128@2x"),
            (256, "icon_256x256"), (512, "icon_256x256@2x"),
            (512, "icon_512x512"), (1024, "icon_512x512@2x"),
        ]
        for (px, name) in sizes {
            let out = NSImage(size: NSSize(width: px, height: px))
            out.lockFocus()
            NSGraphicsContext.current?.imageInterpolation = .high
            master.draw(in: NSRect(x: 0, y: 0, width: px, height: px))
            out.unlockFocus()
            guard let rep = NSBitmapImageRep(data: out.tiffRepresentation!),
                  let png = rep.representation(using: .png, properties: [:]) else { continue }
            try! png.write(to: URL(fileURLWithPath: outDir + "/" + name + ".png"))
        }
        print("書き出し \(sizes.count) 枚 → \(outDir)")
    }

    /// 輪郭の内側を塗り潰してシルエットにする。
    /// 外周から「線でない画素」を辿って外側を求め、外側でないところを中身とする。
    /// ★ 中に浮いている線(目)は、外側に接していない連結成分として抜く。
    ///   全部黒く塗ると顔が消えて、ただの鳥に見える。
    static func silhouette(darkness: [Float], w: Int, h: Int) -> [UInt8] {
        // にじみで穴が開かないよう、塗り分けのしきい値は低めに取る
        let isInk = darkness.map { $0 > 0.20 }

        var outside = [Bool](repeating: false, count: w * h)
        var stack: [Int] = []
        func push(_ x: Int, _ y: Int) {
            let i = y * w + x
            if !outside[i] && !isInk[i] { outside[i] = true; stack.append(i) }
        }
        for x in 0..<w { push(x, 0); push(x, h - 1) }
        for y in 0..<h { push(0, y); push(w - 1, y) }
        while let i = stack.popLast() {
            let x = i % w, y = i / w
            if x > 0 { push(x - 1, y) }
            if x < w - 1 { push(x + 1, y) }
            if y > 0 { push(x, y - 1) }
            if y < h - 1 { push(x, y + 1) }
        }

        // 線の連結成分ごとに、外側に接しているかを見る
        var component = [Int32](repeating: -1, count: w * h)
        var touchesOutside: [Bool] = []
        for start in 0..<(w * h) where isInk[start] && component[start] < 0 {
            let id = Int32(touchesOutside.count)
            var touching = false
            component[start] = id
            var queue = [start]
            while let i = queue.popLast() {
                let x = i % w, y = i / w
                for (dx, dy) in [(-1, 0), (1, 0), (0, -1), (0, 1), (-1, -1), (1, -1), (-1, 1), (1, 1)] {
                    let nx = x + dx, ny = y + dy
                    guard nx >= 0, nx < w, ny >= 0, ny < h else { touching = true; continue }
                    let j = ny * w + nx
                    if outside[j] { touching = true }
                    if isInk[j] && component[j] < 0 { component[j] = id; queue.append(j) }
                }
            }
            touchesOutside.append(touching)
        }
        let interiorCount = touchesOutside.filter { !$0 }.count
        print("  線の連結成分 \(touchesOutside.count) 個 / うち内側だけのもの \(interiorCount) 個(目などとして抜く)")

        var alpha = [UInt8](repeating: 0, count: w * h)
        for i in 0..<(w * h) {
            let id = component[i]
            // 内側に浮いている線は抜く(下地の色が見える)
            if id >= 0 && !touchesOutside[Int(id)] { continue }
            if isInk[i] || !outside[i] { alpha[i] = 255 }
        }
        // ★ しきい値で塗り分けた縁はギザギザになる。元絵とアイコンがほぼ等倍なので
        //   縮小によるならしも効かない。少しぼかして境目だけを滑らかにする。
        return smooth(alpha, w: w, h: h, radius: 2)
    }

    /// 箱ぼかし。中身(255)と外(0)はそのまま、境目だけが中間値になる。
    static func smooth(_ a: [UInt8], w: Int, h: Int, radius: Int) -> [UInt8] {
        var tmp = [Float](repeating: 0, count: w * h)
        var out = [UInt8](repeating: 0, count: w * h)
        let n = Float(radius * 2 + 1)
        for y in 0..<h {                                  // 横
            for x in 0..<w {
                var sum: Float = 0
                for d in -radius...radius {
                    sum += Float(a[y * w + Swift.min(Swift.max(x + d, 0), w - 1)])
                }
                tmp[y * w + x] = sum / n
            }
        }
        for x in 0..<w {                                  // 縦
            for y in 0..<h {
                var sum: Float = 0
                for d in -radius...radius {
                    sum += tmp[Swift.min(Swift.max(y + d, 0), h - 1) * w + x]
                }
                out[y * w + x] = UInt8(Swift.max(0, Swift.min(255, sum / n)))
            }
        }
        return out
    }

    static func image(alpha: [UInt8], w: Int, h: Int, bounds: NSRect) -> NSImage {
        let x0 = Int(bounds.minX), y0 = Int(bounds.minY)
        let bw = Int(bounds.width), bh = Int(bounds.height)
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: bw, pixelsHigh: bh,
                                   bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                   isPlanar: false, colorSpaceName: .deviceRGB,
                                   bytesPerRow: bw * 4, bitsPerPixel: 32)!
        let data = rep.bitmapData!
        for y in 0..<bh {
            for x in 0..<bw {
                let o = (y * bw + x) * 4
                data[o] = 0; data[o + 1] = 0; data[o + 2] = 0
                data[o + 3] = alpha[(y0 + y) * w + (x0 + x)]
            }
        }
        let img = NSImage(size: NSSize(width: bw, height: bh))
        img.addRepresentation(rep)
        return img
    }

    static func hex(_ c: NSColor) -> String {
        String(format: "#%02X%02X%02X",
               Int(c.redComponent * 255), Int(c.greenComponent * 255), Int(c.blueComponent * 255))
    }
}
