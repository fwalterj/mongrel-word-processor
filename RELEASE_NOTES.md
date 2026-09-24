# Confident build 1.0.0 (3)

September 24, 2026. A universal test release for macOS 14 Sonoma or later on Apple Silicon and Intel.

## Install

Download the DMG from [GitHub Releases](https://github.com/fwalterj/mongrel-word-processor/releases), drag **Mongrel Word Processor** into **Applications**, eject the image, and open the installed app. Quit an older version before replacing it. Documents and recovered drafts are stored separately from the application. A ZIP of the same app is also available.

The app and disk image are Developer ID signed, notarized by Apple, and include stapled tickets. Both passed Gatekeeper checks. Compare downloaded assets against `SHA256SUMS` when needed.

## Included

- Black and White Contrast across prose, screenplay, and source editing, with Black as the default for new preferences. Clear active tabs, screenplay scenes, formatting states, and page boundaries.
- A bounded recent-document sidebar, useful folder labels, readable bulk screenplay pastes, and a matching app icon.
- Faster large-source editing, cached syntax tokenization, guarded native completion, and recovery that keeps only the newest queued snapshot.
- Fixes for recursive completion crashes, Return before emoji, selection boundaries during indentation, imported line endings, and stale native completion ranges.
- Persistent sandbox access to files selected by the user, mixed-mode workspace recovery, independent tab undo, screenplay production identities, native document metadata, and attachment/Unicode preservation.
- Bundled offline dictionary with 529,414 headwords. No account is needed; the optional LanguageTool integration uses a local server.

## Validation and scope

176 repository test methods passed through the standalone native assertion harness, including 240 mixed workspace operations, 55 recovered tabs, 2,000 queued recovery updates, 80 edits in a 488,000 UTF-16-unit source, and exact-text formatting/save/reopen checks for 14 local screenplay PDFs. The PDFs are excluded from this release and repository.

Both CPU architectures compiled optimized with strict concurrency and warnings treated as errors. Live Apple Silicon testing covered Contrast in all three modes, bulk paste, native completion, undo/redo, source-file permissions across relaunch, and installation from the DMG. SharedFoundation is statically linked; the app does not depend on a development folder or temporary library.

Intel was cross-compiled but not run on this machine. A second Mac and older supported macOS versions remain to be tested. Xcode's XCTest runner is blocked by the installed Xcode SDK license; the successful test results came from the documented native fallback harness. Screenplay locked pages, A/B pages, revision sets, and printed omitted-scene placeholders are not implemented.

This is a confident test build, published as a prerelease. The repository remains source-visible without an open-source license grant.
