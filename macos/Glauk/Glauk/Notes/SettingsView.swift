// SettingsView.swift
import SwiftUI
import AppKit

struct SettingsView: View {
    @EnvironmentObject var notesFolder: NotesFolder
    @EnvironmentObject var noteIndex: NoteIndex
    @AppStorage(GlaukTheme.storageKey) private var palette = GlaukTheme.paper.rawValue
    @AppStorage(ThemePreference.storageKey) private var appearance = ThemePreference.auto.rawValue

    var body: some View {
        Form {
            Section("見た目") {
                Picker("テーマ", selection: $palette) {
                    ForEach(GlaukTheme.allCases) { theme in
                        Text(theme.label).tag(theme.rawValue)
                    }
                }
                Text(GlaukTheme(rawValue: palette)?.detail ?? "")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Picker("明るさ", selection: $appearance) {
                    ForEach(ThemePreference.allCases) { pref in
                        Text(pref.label).tag(pref.rawValue)
                    }
                }
                .pickerStyle(.segmented)

                // ★ どのテーマも紙と朱の関係は保つ。見本を出して、名前だけで
                //   選ばせないようにする。
                swatches
            }

            Section("ノートフォルダ") {
                if let root = notesFolder.root {
                    Text(root)
                        .font(.caption)
                        .textSelection(.enabled)
                        .lineLimit(2)
                        .truncationMode(.head)
                    if notesFolder.looksLikeObsidianVault {
                        Label("Obsidian の vault を検出しました", systemImage: "checkmark.circle")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if noteIndex.isScanning {
                        Label("走査中…", systemImage: "arrow.triangle.2.circlepath")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("\(noteIndex.names.count) 件のノート")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    HStack {
                        Button("変更…") { notesFolder.chooseWithPanel() }
                        Button("解除") { notesFolder.clear() }
                    }
                } else {
                    Text("未設定(単一ファイル編集のみ)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button("フォルダを選ぶ…") { notesFolder.chooseWithPanel() }
                }
            }
        }
        .formStyle(.grouped)
        .padding()
        .frame(width: 460)
        .onChange(of: appearance) { _, newValue in
            ThemePreference.apply(ThemePreference(rawValue: newValue) ?? .auto, to: NSApp.keyWindow)
        }
    }

    /// テーマの見本。紙・インク・文字・引用の4色を小さく並べる。
    private var swatches: some View {
        HStack(spacing: 8) {
            ForEach(GlaukTheme.allCases) { theme in
                Button {
                    palette = theme.rawValue
                } label: {
                    VStack(spacing: 4) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(color(theme, "PaperBg", fallback: .white))
                            HStack(spacing: 3) {
                                Circle().fill(color(theme, "InkAccent", fallback: .red))
                                    .frame(width: 7, height: 7)
                                Circle().fill(color(theme, "InkText", fallback: .black))
                                    .frame(width: 7, height: 7)
                                Circle().fill(color(theme, "QuoteText", fallback: .gray))
                                    .frame(width: 7, height: 7)
                            }
                        }
                        .frame(width: 62, height: 34)
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(palette == theme.rawValue ? Color.primary : Color.primary.opacity(0.15),
                                        lineWidth: palette == theme.rawValue ? 2 : 1)
                        )
                        Text(theme.label).font(.caption2)
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 2)
    }

    /// ★ ThemeToken は「今選ばれているテーマ」を返すので、見本には使えない。
    ///   見本は選ばれていないテーマの色も出す必要がある。
    private func color(_ theme: GlaukTheme, _ token: String, fallback: Color) -> Color {
        guard let ns = NSColor(named: theme.name(token)) else { return fallback }
        return Color(nsColor: ns)
    }
}
