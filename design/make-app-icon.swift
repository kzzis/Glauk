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
        guard args.count == 3 else {
            print("usage: make-app-icon source.png output.appiconset|output.imageset")
            exit(2)
        }
        let srcPath = args[1]
        let outDir = args[2]

        guard let src = NSImage(contentsOfFile: srcPath) else {
            print("読み込めない"); exit(1)
        }

        let canvas: CGFloat = 1024
        let plate = NSRect(x: 100, y: 100, width: 824, height: 824)
        let master = NSImage(size: NSSize(width: canvas, height: canvas))
        master.lockFocus()
        NSColor.clear.set()
        NSRect(x: 0, y: 0, width: canvas, height: canvas).fill()
        squircle(in: plate).addClip()
        NSGraphicsContext.current?.imageInterpolation = .high
        src.draw(in: plate, from: .zero, operation: .sourceOver, fraction: 1)
        master.unlockFocus()

        let appIconSizes: [(Int, String)] = [
            (16, "icon_16x16"), (32, "icon_16x16@2x"),
            (32, "icon_32x32"), (64, "icon_32x32@2x"),
            (128, "icon_128x128"), (256, "icon_128x128@2x"),
            (256, "icon_256x256"), (512, "icon_256x256@2x"),
            (512, "icon_512x512"), (1024, "icon_512x512@2x"),
        ]
        let appIconSlots: [(String, String, String)] = [
            ("16x16", "1x", "icon_16x16"), ("16x16", "2x", "icon_16x16@2x"),
            ("32x32", "1x", "icon_32x32"), ("32x32", "2x", "icon_32x32@2x"),
            ("128x128", "1x", "icon_128x128"), ("128x128", "2x", "icon_128x128@2x"),
            ("256x256", "1x", "icon_256x256"), ("256x256", "2x", "icon_256x256@2x"),
            ("512x512", "1x", "icon_512x512"), ("512x512", "2x", "icon_512x512@2x"),
        ]
        let isAppIcon = outDir.hasSuffix(".appiconset")
        let isImageSet = outDir.hasSuffix(".imageset")
        guard isAppIcon || isImageSet else {
            print("出力先は .appiconset または .imageset にしてください")
            exit(2)
        }
        try! FileManager.default.createDirectory(atPath: outDir,
                                                  withIntermediateDirectories: true)

        let sizes = isAppIcon ? appIconSizes : [(512, "icon"), (1024, "icon@2x")]
        let entries = isAppIcon ? appIconSlots.map { size, scale, name in
            """
                {
                  "filename" : "\(name).png",
                  "idiom" : "mac",
                  "scale" : "\(scale)",
                  "size" : "\(size)"
                }
            """
        }.joined(separator: ",\n") : """
                {
                  "filename" : "icon.png",
                  "idiom" : "universal",
                  "scale" : "1x"
                },
                {
                  "filename" : "icon@2x.png",
                  "idiom" : "universal",
                  "scale" : "2x"
                }
        """
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

}
