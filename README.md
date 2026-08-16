<p align="center">
  <img src="docs/icon.png" width="112" alt="">
</p>

<h1 align="center">Glauk</h1>

<p align="center"><em>glaukopis — bright-eyed, owl-eyed.</em></p>

<p align="center">A Markdown editor for macOS, built for the thought you are having right now.</p>

![](docs/editor.png)

## Principles

**Never eat the markup.** Headings, bold, links — the characters you typed stay where you put
them, and only their appearance changes. What you wrote and what you see never drift apart, so
putting the cursor on a line always shows you the source.

**Save quietly.** A moment after you stop typing, the file is written. No indicator, no toast.
You hear about it **only when it fails**.

**One screen.** There are no tabs. Following a link swaps the screen, and ⌘[ takes you back.
The note tree (⌘\\) and the switcher (⌘O) are there when you call them, and fold away when
you don't.

## What works today

`[[links]]` resolve by walking a local folder — no network, no plugins. The syntax follows
Obsidian, so an existing vault opens as it is.

- Headings, bold, lists, checkboxes, quotes, callouts, tables, math, tags, footnotes
- Syntax highlighting for code (diffs are coloured as diffs)
- `[[` completion, link navigation, and creating a missing note on the spot
- Autosave

## What's next

Ink-blue on a desk at night; red pen on paper by day. The theme is still the stock palette.
A global shortcut to summon the window, and edits made by an AI blooming and drying like ink
on the page — those come later too.

## How it's built

Parsing is **Zig**. The UI is **Swift + AppKit** (TextKit 1).

Zig returns nothing but a list of ranges — where each piece of markup starts and ends.
Swift reads that list and applies attributes; it never touches the text storage.
That is why the source survives, and why nothing breaks mid-composition in Japanese input.

```sh
cd core && zig build              # core first
open macos/Glauk/Glauk.xcodeproj
```

Needs Zig 0.15.2 and Xcode. Tests: `cd core && zig test src/root.zig`.

## Getting started

Pick a folder for your notes from the button in the top right, and its notes show up
behind `[[`. Skip it, and Glauk works as a plain single-file editor.
