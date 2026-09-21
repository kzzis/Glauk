import AppKit

@main
struct EditorLinkChecks {
    @MainActor
    static func main() {
        let source = "[first](https://one.test) [second](https://two.test) [[Existing|open note]] [[Missing]] https://three.test [日本語](https://four.test) [[既存|開く]]"
        let storage = NSTextStorage(string: source)
        let highlighter = SyntaxHighlighter()
        highlighter.noteExists = { $0 == "Existing" || $0 == "既存" }
        highlighter.apply(to: storage, cursorLine: nil)

        let ns = source as NSString
        func attribute(_ key: NSAttributedString.Key, in text: String) -> Any? {
            let range = ns.range(of: text)
            precondition(range.location != NSNotFound)
            return storage.attribute(key, at: range.location, effectiveRange: nil)
        }
        func underline(in text: String) -> Int {
            attribute(.underlineStyle, in: text) as? Int ?? 0
        }

        precondition(attribute(.glaukLinkURL, in: "first") as? String == "https://one.test")
        precondition(attribute(.glaukLinkURL, in: "second") as? String == "https://two.test")
        precondition(underline(in: "first") == NSUnderlineStyle.single.rawValue)
        precondition(underline(in: "second") == NSUnderlineStyle.single.rawValue)
        precondition(attribute(.glaukLinkTarget, in: "open note") as? String == "Existing")
        precondition(underline(in: "open note") == NSUnderlineStyle.single.rawValue)
        precondition(underline(in: "Missing") ==
                     NSUnderlineStyle.patternDot.rawValue | NSUnderlineStyle.single.rawValue)
        precondition(underline(in: "https://three.test") == NSUnderlineStyle.single.rawValue)
        precondition(attribute(.glaukLinkURL, in: "日本語") as? String == "https://four.test")
        precondition(underline(in: "日本語") == NSUnderlineStyle.single.rawValue)
        precondition(attribute(.glaukLinkTarget, in: "開く") as? String == "既存")
        precondition(underline(in: "開く") == NSUnderlineStyle.single.rawValue)

        storage.replaceCharacters(in: ns.range(of: "[[Existing|open note]]"), with: "plain text")
        highlighter.apply(to: storage, cursorLine: nil)
        let plain = (storage.string as NSString).range(of: "plain text")
        precondition(storage.attribute(.glaukLinkTarget, at: plain.location,
                                       effectiveRange: nil) == nil)
        print("Editor link checks passed")
    }
}
