# 同梱フォント

ここに `.ttf` / `.otf` を置くと、アプリ起動時に自動登録される
(`INFOPLIST_KEY_ATSApplicationFontsPath = Fonts`)。
`CTFontManagerRegisterFontsForURL` を手で呼ぶ必要はない。

現在このフォルダは空で、フォントは**システムに入っていれば**使われる。
入っていなければ `GlaukFont` が次の候補へ落ち、最後はシステムフォントになる。

| 用途 | 第1候補 | PostScript名 |
|---|---|---|
| 見出し | 幻ノにじみ明朝 | `GenEiNijimiMincho-Regular` |
| 本文 | Inter | `Inter-Regular` |
| コード・AIペイン | IBM Plex Mono | `IBMPlexMono` |

## 置くときの注意

**ファイル名と PostScript名は別物**。`NSFont(name:size:)` に渡すのは
PostScript名で、間違えると黙ってフォールバックが効き、
「同梱したのに反映されない」という分かりにくい状態になる。

```bash
python3 -c "
from fontTools.ttLib import TTFont
f = TTFont('GenEiNijimiMincho-Regular.ttf')
print(next(r.toUnicode() for r in f['name'].names if r.nameID == 6))
"
```

DEBUG ビルドは起動時に `[font] 見出し: …` を出す。
ここが「システムフォントにフォールバック」なら名前が違っている。

幻ノにじみ明朝は SIL Open Font License 1.1 なので同梱・再配布ができる。
置くときはライセンス本文も一緒に入れること。
