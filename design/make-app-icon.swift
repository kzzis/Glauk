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

        guard let src = NSImage(contentsOfFile: srcPath),
              let srcRep = NSBitmapImageRep(data: src.tiffRepresentation!) else {
            print("読み込めない"); exit(1)
        }
        let w = srcRep.pixelsWide, h = srcRep.pixelsHigh

        // --- 背景色と、線の外接矩形を測る ---
        let bg = srcRep.colorAt(x: 2, y: 2)!.usingColorSpace(.sRGB)!
        // ★ 白線/黒地と黒線/白地の両方を受ける。背景が暗ければ「明るい画素が線」。
        //   決め打ちにすると、地の色を反転した素材を渡したときに線が1つも見つからない。
        let inkIsLighter = bg.brightnessComponent < 0.5
        var minX = w, minY = h, maxX = 0, maxY = 0
        for y in 0..<h {
            for x in 0..<w {
                guard let c = srcRep.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { continue }
                let d = inkIsLighter
                    ? c.brightnessComponent - bg.brightnessComponent
                    : bg.brightnessComponent - c.brightnessComponent
                if d > 0.25 {
                    minX = Swift.min(minX, x); maxX = Swift.max(maxX, x)
                    minY = Swift.min(minY, y); maxY = Swift.max(maxY, y)
                }
            }
        }
        guard minX < maxX else { print("線が見つからない"); exit(1) }
        let ink = NSRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
        print("画像 \(w)x\(h)  背景 \(hex(bg))  線は\(inkIsLighter ? "明るい" : "暗い")側  範囲 \(ink)")

        // --- 1024 のマスターを描く ---
        let canvas: CGFloat = 1024
        // Big Sur 以降の慣習: 1024 のうち中身は 824 角
        let plate = NSRect(x: 100, y: 100, width: 824, height: 824)
        let master = NSImage(size: NSSize(width: canvas, height: canvas))
        master.lockFocus()
        NSColor.clear.set()
        NSRect(x: 0, y: 0, width: canvas, height: canvas).fill()

        let shape = squircle(in: plate)
        bg.setFill()
        shape.fill()

        // 梟を正方形の中に収める。
        // ★ 元画像をそのまま切り出して貼ると、背景の色ムラが四角く出てしまう。
        //   線だけを抜き出した透明画像を作って、平らな下地の上に重ねる。
        let stroke = inkMask(srcRep, bounds: ink, background: bg, lighter: inkIsLighter)
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
        // Contents.json も一緒に書く。
        // ★ PNG を置くだけでは駄目で、ここに filename が無いとスロットが空のまま
        //   =アイコンが出ない。手で書くと必ず食い違うので、生成側で面倒を見る。
        let slots: [(String, String, String)] = [
            ("16x16", "1x", "icon_16x16"), ("16x16", "2x", "icon_16x16@2x"),
            ("32x32", "1x", "icon_32x32"), ("32x32", "2x", "icon_32x32@2x"),
            ("128x128", "1x", "icon_128x128"), ("128x128", "2x", "icon_128x128@2x"),
            ("256x256", "1x", "icon_256x256"), ("256x256", "2x", "icon_256x256@2x"),
            ("512x512", "1x", "icon_512x512"), ("512x512", "2x", "icon_512x512@2x"),
        ]
        let entries = slots.map { size, scale, name in
            """
                {
                  "filename" : "\(name).png",
                  "idiom" : "mac",
                  "scale" : "\(scale)",
                  "size" : "\(size)"
                }
            """
        }.joined(separator: ",\n")
        let contents = """
        {
          "images" : [
        \(entries)
          ],
          "info" : {
            "author" : "xcode",
            "version" : 1
          }
        }

        """
        try! contents.write(toFile: outDir + "/Contents.json", atomically: false, encoding: .utf8)

        var written: Set<String> = []
        for (px, name) in sizes {
            let out = NSImage(size: NSSize(width: px, height: px))
            out.lockFocus()
            NSGraphicsContext.current?.imageInterpolation = .high
            master.draw(in: NSRect(x: 0, y: 0, width: px, height: px))
            out.unlockFocus()
            guard let rep = NSBitmapImageRep(data: out.tiffRepresentation!),
                  let png = rep.representation(using: .png, properties: [:]) else { continue }
            let path = outDir + "/" + name + ".png"
            try! png.write(to: URL(fileURLWithPath: path))
            written.insert(name)
        }
        print("書き出し \(written.count) 枚 → \(outDir)")
    }

    /// 背景との明るさの差を不透明度にした、線だけの画像を作る。
    /// しきい値で2値化するとギザギザになるので、差をそのまま alpha にする。
    /// 線の色は背景の逆側に振り切った色(暗い地なら白、明るい地なら黒)。
    static func inkMask(_ rep: NSBitmapImageRep, bounds: NSRect,
                        background: NSColor, lighter: Bool) -> NSImage {
        let x0 = Int(bounds.minX), y0 = Int(bounds.minY)
        let w = Int(bounds.width), h = Int(bounds.height)
        let out = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: w, pixelsHigh: h,
                                   bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                   isPlanar: false, colorSpaceName: .deviceRGB,
                                   bytesPerRow: w * 4, bitsPerPixel: 32)!
        let bgBrightness = background.brightnessComponent
        // 振り切ったところで alpha=1 になるように正規化する
        let span = lighter
            ? Swift.max(0.94 - bgBrightness, 0.01)
            : Swift.max(bgBrightness - 0.06, 0.01)
        let value = lighter ? 255.0 : 0.0
        // 生成画像の圧縮ノイズを拾わないための下限。素の差をそのまま使うと、
        // 地のわずかなムラが白い染みになって出る。
        let floor = 0.05
        let data = out.bitmapData!
        for y in 0..<h {
            for x in 0..<w {
                let b = rep.colorAt(x: x0 + x, y: y0 + y)?.usingColorSpace(.sRGB)?.brightnessComponent
                    ?? bgBrightness
                let raw = (lighter ? b - bgBrightness : bgBrightness - b) / span
                let d = Swift.max(0, Swift.min(1, (raw - floor) / (1 - floor)))
                let o = (y * w + x) * 4
                // ★ NSBitmapImageRep の既定はプリマルチプライド。白を素の 255 で
                //   置くと縁が破綻する(黒線のときは 0 なので偶然合っていた)。
                let premultiplied = UInt8(value * d)
                data[o] = premultiplied
                data[o + 1] = premultiplied
                data[o + 2] = premultiplied
                data[o + 3] = UInt8(d * 255)
            }
        }
        let img = NSImage(size: NSSize(width: w, height: h))
        img.addRepresentation(out)
        return img
    }

    static func hex(_ c: NSColor) -> String {
        String(format: "#%02X%02X%02X",
               Int(c.redComponent * 255), Int(c.greenComponent * 255), Int(c.blueComponent * 255))
    }
}
