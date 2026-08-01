// ContentView.swift
import SwiftUI

struct ContentView: View {
    @State private var text = "# 見出し\n\n本文を書く。**太字** も試す。\n"

    var body: some View {
        MarkdownTextView(text: $text)
            .frame(minWidth: 900, minHeight: 700)
    }
}
