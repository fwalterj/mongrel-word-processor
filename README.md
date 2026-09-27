# Mongrel Word Processor

A native macOS writing environment that treats prose and screenplays as first-class documents. Mongrel Word Processor is an in-progress, source-visible member of the Mongrel suite, built for local work rather than an account, cloud, or App Store funnel.

## Install the confident build

Download the universal DMG from [GitHub Releases](https://github.com/fwalterj/mongrel-word-processor/releases), drag **Mongrel Word Processor** into **Applications**, eject the image, and open the app from Applications. Requires macOS 14 Sonoma or later on Apple Silicon or Intel. Quit an older version before replacing it; documents and workspace recovery are stored separately from the application.

The release assets include a Developer ID signed, notarized DMG and a ZIP of the same app, plus checksums and validation notes. No account is required. The dictionary and all three editing modes work offline; LanguageTool remains an optional local integration.

## What works

- Native prose, coding, and screenplay authoring modes.
- Mixed-mode workspace tabs for keeping prose, screenplay, and coding projects live together, with independent tab duplication and file actions.
- Autosave-on-tab-switch for named files, plus versioned local workspace recovery for untitled and dirty tabs.
- True US Letter screenplay pages with live page and scene counts.
- Scene heading, action, character, parenthetical, dialogue, transition, shot, insert/title card, and time-jump elements.
- Contextual screenplay suggestions, Tab/Shift-Tab element cycling, and whole-document auto-formatting.
- A scene navigator that jumps directly to detected headings.
- A Save As Type menu for native Mongrel files, RTF/RTFD, DOCX, source code, and plain text.
- Native `.mongreldoc` prose masters that retain page colors, headers, footers, attachments, and mode metadata.
- Native `.mgscreenplay` files that retain semantic screenplay elements other formats cannot preserve.
- PDF, DOCX, RTF, and plain-text export.
- Focus and typewriter modes, zoom controls, recent documents, and a command palette.
- A responsive coding canvas with language-aware editing plus live file, storage, line-ending, wrap, cursor, and selection status.
- Black/White Contrast across the workspace and all three editors, plus standard and custom viewing palettes.
- Document insights for reading time, paragraph rhythm, sentence density, scene weight, dialogue share, and character cue counts.
- App-managed OpenType and TrueType font installation, using local font files whose licenses permit use.
- Offline macOS spelling and grammar with a bundled Mongrel Dictionary companion lexicon, plus an optional local LanguageTool check.

## Stack

| Layer | Technology |
|---|---|
| Language | Swift 5.9 |
| Text engine | TextKit 2 (`NSTextView` and `NSTextLayoutManager`) |
| UI | SwiftUI and AppKit |
| Project generation | XcodeGen |
| Platform | macOS 14+, Apple Silicon and Intel |

## Build

Open `MongrelWordProcessor/MongrelWordProcessor.xcodeproj`, select the `MongrelWordProcessor` scheme, and run. The visual foundation needed by the app is included under `MongrelWordProcessor/Packages/SharedFoundation`, so a clone does not depend on another Mongrel repository.

To regenerate the project after changing `project.yml`:

```bash
cd MongrelWordProcessor
xcodegen generate
```

Run the automated suite with:

```bash
cd MongrelWordProcessor
xcodebuild test \
  -project MongrelWordProcessor.xcodeproj \
  -scheme MongrelWordProcessor \
  -destination 'platform=macOS' \
  CODE_SIGNING_ALLOWED=NO
```

## Dictionary companion

The bundled lexicon allows comprehensive offline spellcheck without absorbing the Dictionary app into this repository. When the Dictionary project produces a newer companion export, import it with:

```bash
./Scripts/import-dictionary-companion.sh
```

The app uses the system spellchecker for editor integration and augments it with 529,414 Mongrel Dictionary headwords. Hunspell's source tree is therefore not bundled: the engine alone does not provide a dictionary, while embedding another native spelling stack would duplicate working offline behavior.

## Formats

No single format wins every game:

| Format | Best use | Tradeoff |
|---|---|---|
| `.mongreldoc` | Prose or code master with Mongrel layout | Mongrel-specific outside the app |
| `.mgscreenplay` | Screenplay master | Mongrel-specific outside the app |
| `.rtf` | Portable editable prose | Less universal than DOCX in office workflows |
| `.docx` | Sharing with Word and other suites | Conversion can alter advanced layout or app-specific semantics |
| `.txt` | Code, notes, archival portability | No typography, styles, or screenplay metadata |
| `.pdf` | Fixed-layout delivery and review | Not an authoring format |

Keep prose masters with native layout as `.mongreldoc` and screenplay masters as `.mgscreenplay`; use DOCX, RTF, TXT, or PDF as interchange and delivery copies.

## Fonts and local grammar

Use **Writing > Install Font Files** to copy `.otf` or `.ttf` files into the app's private font library. Mongrel registers them locally on launch rather than silently installing them system-wide. Font licenses still apply, and recipients need the same font unless the delivery format embeds it.

The Writing Tools panel can query a LanguageTool server at `http://127.0.0.1:8081/v2/check`. This keeps text on the Mac and keeps LanguageTool's Java runtime out of the application bundle. Install a standalone LanguageTool release, start its local HTTP server on port 8081, then run the check from Mongrel. The upstream source checkout is useful for development, but it is not itself a distributable server binary.

## Status

This is development software, not a finished release. File creation, mixed-mode tabs, workspace recovery, saving, RTF and DOCX round trips, screenplay semantics, pagination, export, accessibility palettes, and editor integration have automated coverage. Destructive editing and unusual import files still deserve real-world testing before a public beta binary.

The source is currently viewable, but no open-source license has been granted yet.

## Screenplay workspace and reliability polish

The **Classic** (or current voice) button opens the screenplay workspace. Production type, draft stage, and page voice are independent document settings. Voice changes the action-density observations; it never rewrites prose or changes element semantics. Production type currently labels the project; specialized multicamera layouts are not implemented.

- Working and reader/spec drafts default to unnumbered scenes. Scene counts and scene numbers can each be shown or hidden independently.
- Production drafts assign persistent scene identities. Inserted scenes receive letter suffixes, and deleted scene numbers remain reserved in an omitted-scene list. Numbers appear in the editor margins and PDF output without entering the authored text.
- **Production scope:** pages still repaginate. Locked pages, A/B page insertion, revision sets/marks, and an omitted scene's placeholder on the printed page are not implemented. The omitted list is retained as document metadata.
- Characters and locations are collected without the former eight-character limit. Character cue extensions such as V.O., O.S., and curly-apostrophe CONT’D resolve to the same character. Existing headings are available as suggestions.
- Multiline paste formats the pasted paragraphs as a batch. Explicit element choices survive automatic formatting, and action/dialogue emphasis is preserved.
- Native files now use version 2, preserving draft settings, production identities, explicit element choices, attachments, and control/object-marker characters that RTF alone can discard. Version 1 documents remain readable. Older Mongrel builds may not open version 2 files; use an interchange export when needed.

Typing defers document analysis and pagination until a short idle interval. Cursor movement no longer triggers full-document pagination. Recovery caches unchanged tabs and writes snapshots on a serial background queue; closing or leaving the app flushes pending writes. Screenplays have one vertical scrolling surface, and prose follows the available viewport width.

The follow-up reliability pass makes heading, strikethrough, screenplay element, and suggestion actions undoable. Suggestions preserve the following paragraph and its line ending. New tabs reset their typing style, each editor uses an independent undo manager, and the tab strip follows the active document. If a previously saved file becomes unreadable, recovery opens its cached draft as an unsaved copy instead of treating it as safely saved.

## Contrast appearance

Contrast now applies to the active document as well as the workspace: prose, screenplay, and code share the same Black or White surface. New appearance preferences default to **Black** with white text and accents; existing saved palette choices are retained. Use **Black / White** beside the zoom controls, or choose the surface in Appearance settings. The preference follows tab changes and survives relaunch.

The presentation uses crisp type, fine rules, restrained page edges, and inverted active tabs and formatting controls. Code distinguishes syntax with neutral shades, keyword weight, and italic comments. Screenplay margins and page furniture follow the selected surface. Focus controls sit above the document without obscuring its contents; **Cmd-Shift-F** toggles focus from either toolbar layout, and **Esc** exits.

Contrast is a display preference. It does not rewrite document colors, formatting, clipboard contents, or undo history. Colored highlights remain visible in neutral tones while their original colors remain in the file. **Page Layout** controls saved page colors and the colors used for PDF and printing. Choosing another appearance palette restores the document's working colors and the selected coding theme.

## Confident build — 1.0.0 (5)

The September 25 interaction pass fixes magnifier clipping in prose and wrapped code. Zoom, resizing, wrapping, and font changes preserve the selection and reading position; screenplay view zoom leaves print geometry and page counts alone. Font-size controls return focus to the editor and retain undo/redo.

Screenplay Paste now follows the element at the insertion point. External fonts and paragraph geometry are removed while inline emphasis remains. Native screenplay copies retain their element metadata. Use **Screenplay → Paste and Parse Screenplay** when you want a plain-text script interpreted as scenes, action, cues, and dialogue. The scene navigator and catalog respect assigned elements, so an `INT.` line inside Dialogue is not silently counted as a scene.

198 repository test methods passed through the native fallback harness. The September 27 pass adds Word formatting round trips, sparse syntax updates, cached line positions, and viewport materialization after reflow. Live checks include a 2,000-paragraph Word document and a 533,890-character source file, including zoom at the file end. See [editor behavior](EDITOR_BEHAVIOR.md) and [release notes](RELEASE_NOTES.md).

### Earlier hardening retained

The September 24 pass keeps recent documents in a bounded sidebar list, shows their parent folders, and marks the current screenplay scene with the same inverted selection used by the tabs. Bulk paste, formatting, undo, and redo refresh the whole affected presentation so long screenplays remain readable in both Contrast surfaces. Ordinary typing still refreshes only its active paragraph.

Large source files defer syntax coloring until a short typing pause. A cached, single-pass tokenizer keeps comments and quoted strings from interfering with one another. Native completion now handles its own nested text notifications safely, offers automatic suggestions only for incomplete keyword prefixes, and stays out of undo/redo and marked-text composition. Recovery retains only the newest waiting snapshot when writing falls behind; quit still flushes pending work.

Create a self-contained universal app for macOS 14 or later with the installed Command Line Tools:

```bash
./Scripts/build-local-app.sh
```

The script creates a new timestamped directory under `build/` containing the app, ZIP, checksum, and source/build record. An optional argument selects another unused output directory. SharedFoundation is linked statically, and the offline dictionary and Contrast app icon are bundled. This step is ad-hoc signed for local use. Set `MONGREL_ARCHS=arm64` for a faster Apple Silicon-only development build.

The follow-up pass fixes Return before emoji in source files, preserves imported line endings during editing, corrects indentation selection boundaries and line counts, rejects stale completion ranges, and enables persistent sandbox bookmarks for files the user chooses. Ordinary text and RTF formats are registered as alternatives rather than owned formats.

Run the reproducible native fallback checks with `./Scripts/run-native-checks.sh`. It executes the repository's test bodies with setup/teardown and native assertions; it is not the Xcode/XCTest runner. The optional local `screenplay_examples/` corpus is ignored by Git and excluded from all app packages. See `QA_RELEASE_CHECKLIST.md` for validation evidence and the outstanding Xcode license gate.

For distribution, provide a Developer ID Application identity and an existing notarytool Keychain profile:

```bash
SIGNING_IDENTITY='Developer ID Application: YOUR IDENTITY' \
NOTARY_PROFILE='YOUR KEYCHAIN PROFILE' \
./Scripts/package-shareable-app.sh build/YOUR-BUILD-DIRECTORY
```

The packaging script notarizes and staples both the app and installer, checks Gatekeeper acceptance, and creates the universal DMG, ZIP, and checksums. No signing credentials are stored in the repository. Intel code is cross-compiled; runtime validation so far has been on Apple Silicon.

## Word formatting and large documents — 1.0.0 (5)

The September 27 build restores Word paragraph style inheritance, first-line and hanging indents, fonts, spacing, alignment, tab stops, and web links. Word save/reopen retains corrected indentation and line height. Complex Word layout features remain subject to the native converter's limits; see [release notes](RELEASE_NOTES.md).

Large source files retain syntax colouring without rewriting every unchanged formatting run. Line positions are cached, and ordinary scrolling skips redundant viewport geometry work. The new supplied typewriter icon is generated from `Branding/wordproc.png` using `Scripts/render-app-icon.swift` and `iconutil`.
