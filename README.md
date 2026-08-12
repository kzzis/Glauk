<p align="center">
  <img src="docs/icon.png" width="128" alt="Glauk">
</p>

<h1 align="center">Glauk</h1>

<p align="center">Obsidian 互換のリンク体験を、Obsidian なしで。<br>macOS 向けの Markdown エディタ。</p>

---

書いている記法の文字を消さずに、その場で見た目だけを整えます(ライブプレビュー)。
`[[リンク]]` はローカルフォルダを走査して解決するので、**ネットワーク通信も、Obsidian の起動も、プラグインも要りません**。
Obsidian の vault フォルダをそのまま指定できます。

![本文の表示](docs/editor.png)

## できること

- **ライブプレビュー** — 見出し・太字・リスト・チェックボックス・引用・コールアウト・テーブル・数式・タグ・脚注など、Obsidian の記法をひととおり
- **コードのシンタックスハイライト** — Swift / Zig / JS / Python / Rust / Go / C系 / シェル / JSON / YAML / diff
- **`[[` 補完とリンク移動** — vault を走査して候補を出す。クリックで開き、⌘[ で戻る。未作成リンクはその場で作れる
- **ノートツリー(⌘\\)とクイックスイッチャー(⌘O)** — 畳めば単一画面に戻る
- **沈黙する自動保存** — 保存の通知は出さない。失敗したときだけ知らせる

## つくり

| | |
|---|---|
| コア | Zig — Markdown の解析、ファイル入出力、フォルダ走査 |
| UI | Swift + AppKit(TextKit 1)+ SwiftUI |

解析は Zig が「どこからどこまでが何の記法か」という**スパンの一覧**だけを返し、
Swift はそれを見て属性を付けます。テキストは書き換えません。

## ビルド

```sh
cd core && zig build          # 先にコアを作る(Xcode のビルドフェーズからも走ります)
open macos/Glauk/Glauk.xcodeproj
```

```sh
cd core && zig test src/root.zig     # テスト
```

必要なもの: Zig 0.15.2 / Xcode(macOS 26 SDK)

## 使いはじめ

1. 右上の **vault を選ぶ…** から、ノートを置くフォルダを指定します(Obsidian の vault でも構いません)
2. `[[` を打つと、そのフォルダのノートが候補に出ます
3. リンクをクリックすると開き、⌘[ で戻ります

フォルダは任意です。指定しなくても、単一ファイルのエディタとして動きます。
