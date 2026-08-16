<p align="center">
  <img src="docs/icon.png" width="128" alt="Glauk">
</p>

<h1 align="center">Glauk</h1>

<p align="center">リンクでつなぐ、macOS の Markdown エディタ。</p>

![本文の表示](docs/editor.png)

記法の文字を消さずに、見た目だけを整えます。
`[[リンク]]` はローカルフォルダを走査して解決するので、通信もプラグインも要りません。
記法は Obsidian 互換なので、既存の vault をそのまま開けます。

## できること

- ライブプレビュー(見出し・チェックボックス・コールアウト・テーブル・数式・タグなど)
- コードのシンタックスハイライト
- `[[` 補完とリンク移動(⌘[ で戻る)。未作成リンクはその場で作れる
- ノートツリー(⌘\\)とクイックスイッチャー(⌘O)
- 沈黙する自動保存

## つくり

コアは Zig、UI は Swift + AppKit(TextKit 1)。
Zig は「どこからどこまでが何の記法か」だけを返し、Swift が属性を付けます。テキストは書き換えません。

## ビルド

```sh
cd core && zig build
open macos/Glauk/Glauk.xcodeproj
```

Zig 0.15.2 / Xcode が要ります。テストは `cd core && zig test src/root.zig`。

## 使いはじめ

右上のボタンからノートを置くフォルダを指定すると、`[[` にそのノートが出ます。
指定しなくても、単一ファイルのエディタとして動きます。
