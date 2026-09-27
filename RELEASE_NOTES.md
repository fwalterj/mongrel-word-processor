# Confident build 1.0.0 (5)

September 27, 2026. A universal test release for macOS 14 Sonoma or later on Apple Silicon and Intel.

## Install

Download the DMG from [GitHub Releases](https://github.com/fwalterj/mongrel-word-processor/releases), drag **Mongrel Word Processor** into **Applications**, eject the image, and open the installed app. Quit an older version before replacing it. Documents and recovered drafts are stored separately from the application. A ZIP of the same app is also available.

The app and disk image are Developer ID signed, notarized by Apple, and include stapled tickets. Both passed Gatekeeper checks. Compare downloaded assets against `SHA256SUMS` when needed.

## Changed in build 5

- Word imports now resolve inherited paragraph styles and fonts, first-line and hanging indents, left/right indents, alignment, paragraph spacing, line height, and tab stops. Direct formatting overrides inherited values, including explicit zero settings. Web links are restored from Word relationships; native text, images, and table structure are retained.
- Word export preserves first-line/hanging indents and line-height settings through save and reopen. Native Mongrel archives retain these properties too.
- Source editing changes syntax attributes only where formatting actually changed. Multiline lexical context is still checked, so comment edits update later affected lines.
- Cached line positions remove repeated whole-file scans during caret movement and status updates. Ordinary viewport tiling no longer measures or lays out text when the canvas size is unchanged. Explicit zoom and resize retain stable reading anchors.
- Imported text receives a deferred display refresh so it appears in the selected Contrast polarity on first open.
- The supplied typewriter artwork replaces the previous monogram app icon.

## Earlier improvements retained

- Black and White Contrast across prose, screenplay, and source editing, with Black as the default for new preferences. Clear active tabs, screenplay scenes, formatting states, and page boundaries.
- A bounded recent-document sidebar, useful folder labels, readable bulk screenplay pastes, and a matching app icon.
- Faster large-source editing, cached syntax tokenization, guarded native completion, and recovery that keeps only the newest queued snapshot.
- Fixes for recursive completion crashes, Return before emoji, selection boundaries during indentation, imported line endings, and stale native completion ranges.
- Persistent sandbox access to files selected by the user, mixed-mode workspace recovery, independent tab undo, screenplay production identities, native document metadata, and attachment/Unicode preservation.
- Bundled offline dictionary with 529,414 headwords. No account is needed; the optional LanguageTool integration uses a local server.

## Validation and scope

All 198 repository test methods passed through the native assertion harness. The universal Release build compiled with strict concurrency and warnings treated as errors. Live tests covered a 2,000-paragraph Word document and a 533,890-character source file, including initial Contrast rendering, typing, undo, wrapping, and zoom near the document end. The app and installer passed notarization and Gatekeeper. The release validation record accompanies the downloadable build. Coverage includes DOCX style inheritance and direct overrides, paragraph geometry through Word and native archive round trips, tables, links, soft breaks, Unicode, malformed packages, cyclic styles, large-file editing, multiline comment changes, and unchanged viewport work. Existing document lifecycle, recovery, screenplay, Contrast, zoom, selection, and undo checks remain in the suite.

Word interchange is still not a complete Microsoft Word layout engine. Theme fonts, tracked changes, complex numbering, section layouts, headers/footers, and advanced pagination may differ from Word. Retain the original when importing documents that depend on those features. The paragraph correction matches text before applying properties rather than assigning another paragraph's style when native conversion changes the structure.

Intel is cross-compiled but not run on this machine. A second Mac and older supported macOS versions remain to be tested. Xcode's XCTest runner is blocked by the installed Xcode SDK license; checks use the documented native fallback harness. Screenplay locked pages, A/B pages, revision sets, and printed omitted-scene placeholders are not implemented.

This is a confident test build, published as a prerelease. The repository remains source-visible without an open-source license grant.
