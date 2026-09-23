#!/bin/sh
set -eu
repo=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
build_dir=$(mktemp -d "${TMPDIR:-/tmp}/glauk-regression.XXXXXX")
trap 'rm -rf "$build_dir"' EXIT
cd "$repo/core"
zig build
cd "$repo"
xcrun swiftc -parse-as-library -module-cache-path "$build_dir/modules" \
    -I core/zig-out/include -L core/zig-out/lib -lglaukcore \
    macos/Glauk/Glauk/Notes/GlaukFile.swift \
    macos/Glauk/Glauk/Notes/NotesScanner.swift \
    macos/Glauk/Glauk/Notes/NoteIndex.swift \
    macos/Glauk/Glauk/Notes/NoteTree.swift \
    macos/Glauk/Glauk/Editor/DocumentStore.swift \
    macos/Tests/RegressionChecks.swift -o "$build_dir/checks"
"$build_dir/checks"
xcrun swiftc -parse-as-library -module-cache-path "$build_dir/modules" \
    -I core/zig-out/include -L core/zig-out/lib -lglaukcore \
    macos/Glauk/Glauk/Theme/GlaukFont.swift \
    macos/Glauk/Glauk/Theme/GlaukTheme.swift \
    macos/Glauk/Glauk/Theme/ThemeToken.swift \
    macos/Glauk/Glauk/Editor/EditorTypography.swift \
    macos/Glauk/Glauk/Editor/MarkdownSyntax.swift \
    macos/Glauk/Glauk/Editor/NSRange+Range.swift \
    macos/Glauk/Glauk/Editor/SyntaxHighlighter.swift \
    macos/Tests/EditorLinkChecks.swift -o "$build_dir/editor-links"
"$build_dir/editor-links"
