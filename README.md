# Mongrel Word Processor

A native macOS word processor — part of the Mongrel app suite.

## Overview

Mongrel Word Processor is a native document editor built with TextKit 2. It now supports prose, code, and screenplay authoring, plus a companion-lexicon bridge to Mongrel Dictionary for custom spellcheck coverage.

## Stack

| Layer | Technology |
|---|---|
| Language | Swift |
| Text engine | TextKit 2 (NSTextView + NSTextLayoutManager) |
| UI | SwiftUI + AppKit |
| Build | XcodeGen (`project.yml`) |
| Platform | macOS |

## Structure

```
MongrelWordProcessor/
└── App/
    ├── MongrelWordProcessorApp.swift   # @main entry
    ├── Views/
    │   ├── WordProcessorContentView.swift
    │   └── Editor/
    │       └── TextKit2EditorView.swift
    └── ViewModels/
        ├── DocumentSession.swift
        └── FormattingBridge.swift
```

## What was built

### `TextKit2EditorView.swift`
- `NSViewRepresentable` wrapping `NSTextView` wired to a full TextKit 2 stack (`NSTextContentStorage` → `NSTextLayoutManager` → `NSTextContainer`).
- `allowsUndo`, `usesFindBar`, continuous spell-checking, smart quotes, auto-text-replacement all enabled.
- 1.35× line-height paragraph style injected by default.
- Bridges back to SwiftUI via `@Binding var attributedText` and an `onEdit` callback.
- Augments system spellcheck with the Mongrel Dictionary companion lexicon so suite-specific valid words can be ignored and suggested.

### `DocumentSession.swift`
- `AuthoringMode` enum: `.prose` / `.code` / `.screenplay` — switches editor behaviour and toolbar affordances.
- `CodeLanguage` enum: Swift, JavaScript, and more — drives syntax-hint injection.
- `CodeTheme`, `codeUseTabs`, `codeTabWidth`, `codeLineWrap` preferences.
- `RecentDoc` model: `Identifiable + Codable`, stores title, file path, `openedAt` date; exposes `relativeDate` via `RelativeDateTimeFormatter`.
- Screenplay pagination, scene counting, screenplay element switching, and live companion-lexicon status.

### `FormattingBridge.swift`
- Bridges bold/italic/underline/heading formatting commands from SwiftUI toolbar buttons into `NSTextView` attribute mutations without breaking TextKit 2's layout pass.
- Adds screenplay auto-formatting and contextual suggestions for scene headings, shots, inserts, title cards, transitions, and time jumps.

## Dictionary companion import

The word processor can consume the dictionary app's exported companion package without turning the two apps into one repo or one runtime.

```bash
./Scripts/import-dictionary-companion.sh
```

That imports the latest `MongrelDictionaryCompanionPackage` into `MongrelWordProcessor/App/Resources/`.

## Build command

```bash
cd MongrelWordProcessor
xcodegen generate
xcodebuild -project MongrelWordProcessor.xcodeproj \
           -scheme MongrelWordProcessor \
           -destination 'platform=macOS' \
           CODE_SIGNING_ALLOWED=NO build
```

## Build status

Build verified on macOS with `xcodebuild`.

## License

Proprietary — Mongrel Suite
