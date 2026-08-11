// ContentView.swift
import SwiftUI

struct ContentView: View {
    @StateObject private var noteIndex = NoteIndex()
    @State private var text = "# 見出し\n\n本文を書く。**太字** も試す。\n\n[[AS400アイテムマスタ]] と [[存在しないノート]] を並べる。\n"

    var body: some View {
        MarkdownTextView(text: $text, noteIndex: noteIndex)
            .frame(minWidth: 900, minHeight: 700)
            .onAppear { noteIndex.loadMock() }
    }
}
