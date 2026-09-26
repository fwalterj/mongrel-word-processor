# Confident build 1.0.0 (4)

September 25, 2026. A universal test release for macOS 14 Sonoma or later on Apple Silicon and Intel.

## Install

Download the DMG from [GitHub Releases](https://github.com/fwalterj/mongrel-word-processor/releases), drag **Mongrel Word Processor** into **Applications**, eject the image, and open the installed app. Quit an older version before replacing it. Documents and recovered drafts are stored separately from the application. A ZIP of the same app is also available.

The app and disk image are Developer ID signed, notarized by Apple, and include stapled tickets. Both passed Gatekeeper checks. Compare downloaded assets against `SHA256SUMS` when needed.

## Changed in build 4

- Magnifier controls now reflow prose and wrapped source to the visible width, fixing text disappearing past the right edge.
- Zoom and resize preserve a visible caret or reading anchor, selection, and editor focus. Switching source wrapping back on clears sideways scroll. Screenplay zoom preserves its fixed print width and page count; leaving Fit Width starts from the scale actually on screen.
- Text-size buttons resize the selected font runs, preserve their traits, and support separate undo/redo. Formatting actions restore editor focus.
- Ordinary screenplay paste inherits the destination element, strips external paragraph/font geometry and highlights, and retains inline emphasis. Native screenplay copies preserve semantic metadata and scene identity rules. **Screenplay → Paste and Parse Screenplay** explicitly interprets an incoming plain-text script.
- Scene navigation, counts, and catalogs now honor assigned screenplay elements over textual patterns. Dialogue that mentions `INT.` no longer creates a scene.

- Workspace recovery activates saved file access before checking existence or file identity, and captures access bookmarks while the file grant is active. This prevents readable files from being detached as recovered drafts on relaunch.

## Earlier improvements retained

- Black and White Contrast across prose, screenplay, and source editing, with Black as the default for new preferences. Clear active tabs, screenplay scenes, formatting states, and page boundaries.
- A bounded recent-document sidebar, useful folder labels, readable bulk screenplay pastes, and a matching app icon.
- Faster large-source editing, cached syntax tokenization, guarded native completion, and recovery that keeps only the newest queued snapshot.
- Fixes for recursive completion crashes, Return before emoji, selection boundaries during indentation, imported line endings, and stale native completion ranges.
- Persistent sandbox access to files selected by the user, mixed-mode workspace recovery, independent tab undo, screenplay production identities, native document metadata, and attachment/Unicode preservation.
- Bundled offline dictionary with 529,414 headwords. No account is needed; the optional LanguageTool integration uses a local server.

## Validation and scope

188 repository test methods passed through the standalone native assertion harness, including 240 mixed workspace operations, 55 recovered tabs, 2,000 queued recovery updates, 80 edits in a 488,000 UTF-16-unit source, and exact-text formatting/save/reopen checks for 14 local screenplay PDFs. The PDFs are excluded from this release and repository.

The new checks cover zoom and resize with selections, reading with an offscreen caret, focus restoration, wrap transitions, page-count invariance, font-size undo/redo, destination-aware plain and rich paste, explicit parsing, native metadata, and consistent scene metrics. A separate 411,693-character TextKit 2 viewport probe retained its caret near the end through 60–200% zoom in 0.24–0.27 seconds per reflow on this Mac. This measures native operations, not total UI latency.

Both CPU architectures compiled optimized with strict concurrency and warnings treated as errors. Live Apple Silicon testing covered Contrast in all three modes, magnifier reflow, selected-text formatting and undo/redo, sidebar changes, long source-line wrapping, screenplay paste, scene navigation, and installation from the DMG. Earlier validation also covered native completion and source-file permissions across relaunch. SharedFoundation is statically linked; the app does not depend on a development folder or temporary library.

Intel was cross-compiled but not run on this machine. A second Mac and older supported macOS versions remain to be tested. Xcode's XCTest runner is blocked by the installed Xcode SDK license; the successful test results came from the documented native fallback harness. Screenplay locked pages, A/B pages, revision sets, and printed omitted-scene placeholders are not implemented.

This is a confident test build, published as a prerelease. The repository remains source-visible without an open-source license grant.
