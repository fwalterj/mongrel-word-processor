# Mongrel Word Processor QA and Release Checklist

## Scope
- Validate document lifecycle reliability and truthful action behavior:
  - New/Open/Reopen/Close across mixed-mode tabs
  - Save/Save As/Export
  - Unsaved-change prompts and dirty-state indicator
  - Workspace recovery and stale last-document bookmarks
  - Workflow audit logging coverage

## Preflight
- [ ] Build succeeds for `MongrelWordProcessor` in Release configuration.
- [ ] App launches without runtime warnings or crashes.
- [ ] Menu command enable/disable states are accurate.
- [ ] Keyboard shortcuts trigger intended actions.
- [ ] Formatting controls remain single-line and horizontally scrollable at the minimum window width.
- [ ] Coding status adapts at narrow widths without clipping the language, filename, or cursor position.

## Document Lifecycle
- [ ] `New Document`, `New Screenplay`, and `New Source File` preserve the current project in its tab.
- [ ] `Open...` accepts multiple files without abandoning dirty or untitled tabs.
- [ ] `Duplicate Tab` creates an independent unsaved copy without sharing the original file URL.
- [ ] Tab context actions reveal named files, copy their paths, and remain unavailable for untitled tabs.
- [ ] `Reopen Last Document` restores last document when available.
- [ ] Stale/invalid reopen bookmark is handled gracefully and clears invalid persisted reference.
- [ ] Closing a dirty tab follows Save/Discard/Cancel correctly; cancelling restores prior focus.
- [ ] Closing a clean background tab does not steal focus.
- [ ] Reopen Closed Tab restores content without creating duplicate ownership of an open file.

## Save and Export
- [ ] `Save` writes to current path and clears unsaved indicator.
- [ ] `Save As...` writes to chosen path and updates current document tracking.
- [ ] `Export PDF` succeeds for non-empty and empty documents.
- [ ] `Export Plain Text` and `Export RTF` produce valid files.
- [ ] Save/export failures produce clear user-visible alerts.

## Dirty State and UX Truthfulness
- [ ] Editing title marks document dirty only for user changes.
- [ ] Editing body marks document dirty.
- [ ] Programmatic state updates (open/save/new) do not incorrectly mark dirty.
- [ ] Unsaved badge appears only when there are unsaved changes.

## Filename and IO Integrity
- [ ] Suggested filenames sanitize unsafe characters and never produce empty stem.
- [ ] Save/export correctly infer and honor selected type.
- [ ] Loading malformed/unsupported content fails with explicit feedback.

## Reopen/Persistence Integrity
- [ ] Last-document bookmark updates after successful open and save.
- [ ] Reopen works across app relaunch.
- [ ] Reopen remains disabled when no valid persisted bookmark exists.
- [ ] Mixed named and untitled tabs restore in their prior order and mode after relaunch.
- [ ] Dirty recovery content wins over the disk copy; clean named tabs reload the latest disk content.
- [ ] A deleted named file is restored as an unsaved recovered copy.
- [ ] Corrupt or oversized recovery data is quarantined and the app starts clean.
- [ ] A single pristine blank workspace does not leave a recovery manifest.

## Tab Autosave
- [ ] Autosave-on-switch saves dirty named files without prompting.
- [ ] Untitled tabs remain dirty and never trigger an unsolicited Save panel.
- [ ] Autosave skips interchange formats when native headers, footers, or page colors would be lost.
- [ ] Save As refuses to overwrite a path owned by another open tab.

## Logging and Diagnostics
- [ ] Workflow events are logged for open/reopen/new/close/save/export operations.
- [ ] Failure events include useful metadata for triage.

## Regression Pass
- [ ] Toolbar actions still map exactly to session methods.
- [ ] Command menu and toolbar remain behaviorally consistent.
- [ ] Text editor remains editable with undo and no rendering regressions.

## Screenplay and Heavy-Use Regression Additions

- [ ] Paste a complete screenplay, undo once, redo, and confirm all paragraphs and words return.
- [ ] Paste in a scene-heading paragraph and confirm action/dialogue do not inherit heading bold.
- [ ] Mark an uppercase impact line as Action; Auto Format and save/reopen preserve that choice.
- [ ] Switch between several screenplay/prose tabs, including identical text; undo cannot edit the other tab.
- [ ] Resize a prose window and verify the text remains visible and follows the viewport width.
- [ ] Jump between screenplay scenes without a second vertical scroll view hiding the text.
- [ ] Toggle scene counts independently of printed scene numbers.
- [ ] Switch Classic/Literary/Momentum independently of Working/Reader/Production; prose remains identical.
- [ ] Insert, move, and delete production scenes; existing identities and reserved omitted numbers survive saving and recovery.
- [ ] Verify left/right scene-number placement in the editor and PDF, including subsequent pages.
- [ ] Check native round trips for CRLF, control characters, bare object markers, emoji, and actual image attachments.
- [ ] Recover more than fifty tabs and a large Unicode prose document without dropping the workspace.
- [ ] Exercise the local `screenplay_examples` PDF corpus through extraction, multiline formatting, native save, and reopen; compare exact text. These tests do not assert perfect semantic inference from PDF layout.

Native test additions are in `ScreenplayPolishTests.swift` and `ScreenplayEditorIntegrationTests.swift`. The sample corpus is optional and remains local; its contents are not bundled into the application.

### Validation evidence for the screenplay polish

- Full optimized native app build and strict-concurrency source check passed using the installed Command Line Tools SDK.
- All 141 repository test methods passed through a temporary standalone native assertion harness. This executes the test bodies with setup/teardown and assertion checking; it is not an Xcode/XCTest runner result. Xcode's own build/test workflow remains blocked by its unaccepted SDK license.
- All 14 local sample PDFs passed extraction, multiline formatting, native save, and reopen with exact text equality. The largest extracted sample contained 343,354 UTF-16 units. Formatting plus save took approximately 0.19–0.69 seconds per sample on the validation machine; these are operation timings, not end-to-end UI latency measurements.
- Native regression coverage includes large Unicode prose, rapid mixed-mode tab operations, recovery above fifty tabs, scene identity through edits/copy/cut, attachments, control characters, and production-number PDF output.
- An isolated test app verified visible prose text, screenplay scrolling, multiline paste and single-step undo/redo, tab switching, independent voice/draft controls, and scene numbers in both editor margins. PDF output was rendered and visually inspected.
- Production scene identities and omitted-number reservations are implemented. Locked pages, A/B pages, printed omitted-scene placeholders, and revision sets are not implemented. Production-format categories currently record intent without selecting distinct TV page layouts; page voices change rhythm observations without rewriting text.

These checks support the tested workflows; they are not a guarantee against every possible crash or a substitute for the remaining release checklist.

### Follow-up reliability and interaction pass

- [ ] Apply H1 or strikethrough, then undo and redo; text and formatting return exactly.
- [ ] Change a screenplay element or accept a heading suggestion, then undo and redo. The following paragraph must remain separate, including CRLF imports.
- [ ] Explicitly mark an uppercase action line as Action, then use Auto with the real editor delegate attached; the manual choice survives.
- [ ] Enter a heading containing a length-changing Unicode case conversion (such as ß), then undo. No characters should remain after undoing an insertion into an empty document.
- [ ] Create a prose tab after editing a heading; new typing starts with the normal body font. Switching authoring modes must not expose another editor's undo actions.
- [ ] Create enough tabs to overflow the tab strip, then navigate by keyboard; the active tab stays visible. Close prompts identify the document.
- [ ] Corrupt a clean native file after saving a recovery snapshot; relaunch opens the cached text as an unsaved recovered copy and leaves the damaged file untouched.
- [ ] Recover a manifest with duplicate tab identifiers; each recovered draft receives independent ownership.

The repeatable lifecycle stress test performs 240 mixed operations and checks document contents against an independent expected-state map, including periodic recovery. Editor regressions also cover immutable published snapshots and overflow-safe selection requests.

Validation result: **154 test methods passed with zero assertion failures**, including the 240-operation lifecycle test and all 14 local screenplay samples. The optimized native app build passed with strict concurrency enabled. Tests ran through the standalone native harness described above; Xcode/XCTest remains blocked by the unaccepted SDK license. The isolated live app additionally verified native saving, formatting and suggestion undo/redo, fresh-tab body styling, named close prompts, and rapid keyboard navigation across 13 tabs. Automatic formatting also retains Unicode paragraph separators. No crash occurred in these tested workflows.

### Contrast appearance and use-case refinement

- [x] New isolated preferences select Contrast / Black; White and other explicit palette choices persist.
- [x] Black and White apply to prose, screenplay, and code, including caret, selection, hyperlinks, page furniture, and neutral syntax.
- [x] Appearance changes leave source attributed text, selection, undo/redo, and native saved colors intact. Imported highlights retain their stored colors and receive readable neutral display fills.
- [x] Multiline paste without a trailing newline and continued typing remain visible. Live testing found and fixed AppKit replacing the active paragraph's rendering attributes; the repair refreshes that paragraph without invalidating the full document.
- [x] Active tabs and formatting states invert clearly in both polarities; text is crisp without the former Contrast glow.
- [x] Both surfaces were visually inspected in all three native editors. Heading formatting, scene navigation, code selections, tab switching, and preference persistence were exercised.
- [x] Focus controls do not obscure document or code headers, and their Black/White labels remain fully visible. Cmd-Shift-F works from the compact toolbar; Esc returns to the workspace.
- [x] An unsaved code document's header follows its title.

Validation: **160 repository test methods passed with zero assertion failures**, including the 240-operation lifecycle workload and exact-text save/reopen checks for all 14 local screenplay PDFs. The final optimized native app and shared UI module compiled without warnings with strict concurrency checking. Test methods ran through the standalone native assertion harness described above, not the Xcode/XCTest runner; that workflow remains blocked by the unaccepted Xcode SDK license. The isolated native preview was rebuilt and exercised after the final changes. No crash occurred in these workflows, and no matching app crash report was found. `git diff --check` passed.

### Confident local build 1.0.0 (2) — September 24, 2026

- [x] Recent documents retain a bounded, independently scrollable area; screenplay scenes and document stats remain visible with six recent entries.
- [x] Recent items show their parent folder and expose the full path in help. The current screenplay scene inverts in both Contrast surfaces.
- [x] Paste an 18-scene screenplay with trailing blank paragraphs; all visible headings, action, characters, and dialogue remain readable immediately after formatting. A regression checks rendering attributes for every paragraph.
- [x] Inspect prose, screenplay, and an 8,000-line source file in Black and White. Appearance follows tab changes and survives relaunch.
- [x] Native code completion can synchronously reenter the text-change delegate without recursively requesting completion. Verify its inserted text is published once. Undo/redo and composition do not request automatic completion.
- [x] Completion scans are bounded and automatic suggestions require an incomplete keyword prefix. Comments, strings, and ordinary identifiers do not unnecessarily invoke the system completion service.
- [x] Code comments containing quotes and keywords tokenize correctly; deleting the entire document retains the Contrast caret.
- [x] Perform 80 native edits in a 488,000 UTF-16-unit code document, undo/redo, flush deferred highlighting, and verify the final immutable snapshot and native save/reopen. The edit burst took about 1.01 seconds on this machine; this is an operation timing, not an end-to-end UI latency measurement.
- [x] Hold the recovery writer busy while 2,000 updates arrive. Only the running snapshot and newest pending snapshot are written; flush waits for completion and subsequent writes still work.
- [x] Repeat the 240-operation mixed-tab lifecycle, 55-tab recovery, Unicode and attachment round trips, and all 14 local screenplay sample extraction/format/save/reopen checks.
- [x] Launch a copy of the actual packaged app with an isolated bundle identity and the normal sandbox. Confirm the bundled 529,414-headword dictionary loads, native completion and undo/redo work in the large source, and eight test drafts plus the latest source edits survive relaunch.
- [x] Verify the final app's strict code signature, ZIP checksum, and system-only dynamic dependencies; no temporary SharedFoundation library is required at runtime.

**Result: 170 repository test methods, zero assertion failures.** The optimized app and SharedFoundation compiled with strict concurrency and warnings treated as errors. Tests used the standalone native assertion harness; Xcode/XCTest is still blocked by the unaccepted Xcode SDK license. The build is Apple Silicon, ad-hoc signed with the sandbox and hardened runtime, and not notarized.

Live testing of an intermediate candidate exposed a stack overflow from recursively requesting native completion inside `textDidChange`. The crash report identified the repeated AppKit completion/delegate frames. The final candidate guards before entering completion, passed a focused synchronous-reentry regression, and survived the same live typing path. The later bulk-screenplay rendering defect was also fixed and retested. No new matching crash report appeared during final-candidate testing. The isolated test app was closed at the end; the user's other running app was left alone.

The deliverable and detailed evidence are under `build/Confident-1.0.0-2/`. Earlier `QA-before-*` directories are superseded diagnostic candidates and are not release artifacts.

### Shareable confident build 1.0.0 (3) — September 24, 2026

- [x] Return before an emoji no longer force-unwraps a UTF-16 surrogate. A native editor test and a live signed-app edit preserve the emoji without crashing.
- [x] Indent/outdent maps both ends of a selection correctly, including a cursor inside indentation and selections ending at the document boundary.
- [x] Return and Duplicate Line retain CRLF, CR, and Unicode line endings. Code line counts include imported Windows line breaks. A live indent/outdent/save cycle retained the exact original UTF-8 bytes and CRLF endings.
- [x] Stale, missing, and overflowing completion ranges return no suggestions instead of slicing outside the document.
- [x] Persistent file bookmarks are enabled in the sandbox entitlements. A fresh Developer ID signed test app opened a source file through the native panel, quit, reopened the latest disk version, and saved another edit without another file picker.
- [x] A Contrast monogram appears in the app bundle; native and generated Xcode projects both include the icon. Ordinary text and RTF formats use the Alternate handler rank.
- [x] Both arm64 and x86_64 app slices compile optimized with complete strict-concurrency checks and warnings treated as errors. The app uses system-only dynamic libraries; SharedFoundation is linked statically.
- [x] Apple accepted separate notarization submissions for the app and DMG. Both tickets were stapled and validated; Gatekeeper accepted the app and installer as Notarized Developer ID.
- [x] The read-only DMG mounted successfully, contained the app and Applications shortcut, and its app passed signature and Gatekeeper checks. That copy was installed in `/Applications/Mongrel Word Processor.app` and launched successfully after ejecting the image.
- [x] The previous running app was closed normally and its recovery manifest backed up locally before installation. The new app retained the workspace, including a recovered draft whose original backing file no longer exists.
- [x] Eight superseded build/cache locations were moved with macOS's recoverable Trash operation. Source, documents, preferences, and the current build were retained.

**176 repository test methods passed with zero assertion failures**, including the existing heavy-use workloads and all 14 local screenplay samples. `Scripts/run-native-checks.sh` now makes the standalone fallback validation repeatable from a checkout. The test corpus remains local and ignored by Git. No new matching crash report appeared during this pass.

The shareable assets are in `build/Confident-1.0.0-3/`; build 2 and the older QA candidates were moved to Trash. Intel was cross-compiled, not executed: this Mac does not have Rosetta installed. Runtime testing was on Apple Silicon; older supported macOS releases and a second physical Mac remain untested. Xcode/XCTest still requires the user to accept the installed Xcode SDK license. These limits do not affect the notarization and Gatekeeper checks that passed for this package.


## September 25 interaction pass — confident build 1.0.0 (4)

- [x] Reproduced and fixed zoom clipping in prose and wrapped code. Character-based viewport anchors preserve selection and reading position through zoom, resize, and wrapping changes.
- [x] Verified fixed screenplay page width and page counts across 60–200% display zoom; manual zoom from Fit Width starts at the displayed scale.
- [x] Corrected font-size actions, focus restoration, and undo/redo. Confirmed selected text survives native fullscreen entry/exit.
- [x] Routed actual native Paste commands through destination-aware screenplay semantics. External paragraph/font geometry is removed while supported inline emphasis remains.
- [x] Added explicit Paste and Parse Screenplay. Parsed/native content cannot inherit a conflicting destination element; toolbar state is reported after the edit and after undo/redo.
- [x] Scene counts, navigation, and catalogs respect assigned elements instead of reinterpreting Dialogue as a scene from its text.
- [x] Corrected security-scoped recovery: activate access before checking file existence/identity and while capturing bookmarks. Verified clean and dirty named documents across repeated sandboxed quit/relaunch cycles.
- [x] All 188 repository test methods passed through the native fallback harness, including existing heavy-use workloads and all 14 local PDF samples. A separate 411,693-unit viewport probe retained a caret near the end through four reflows in 0.24–0.27 seconds each on the validation Mac.
- [x] Optimized universal build, strict concurrency, warnings-as-errors, regenerated project, source hash verification, and git diff --check passed.
- [x] Developer ID signing, Apple notarization, stapled app/DMG tickets, and Gatekeeper acceptance passed. Installed from the DMG and verified the installed executable matches the package.
- [x] Existing workspace was backed up and its original three-tab state preserved. Two missing access bookmarks were refreshed; exact text equality was verified before removing duplicate recovery entries. Saved connections persisted through another relaunch.
- [x] Older local builds and temporary fixtures moved to recoverable Trash. No new matching crash reports found.

Detailed evidence is packaged in `build/Confident-1.0.0-4/VALIDATION.md`. Intel remains cross-compiled only; second-Mac and older-macOS runtime checks remain open. Xcode/XCTest still requires acceptance of the installed SDK license; the successful results above came from the native fallback harness.

## Word and large-file regression pass

- [x] Open the generated WordFormatting.docx fixture directly into Black Contrast; verify first paint, then White Contrast.
- [x] Verify first-line, hanging, inherited, and zero-reset indents; spacing, tabs, font overrides, links, and table cells.
- [x] Save as DOCX and native Mongrel format, reopen, and compare paragraph geometry.
- [x] Exercise a 2,000-paragraph Word file and a 500,000+ character source: end navigation, typing, undo, scroll, zoom, wrap, tab switching, and relaunch.
- [x] Confirm syntax changes affect adjacent/multiline context without rewriting unrelated paragraph formatting.
- [x] Check the supplied typewriter icon in the bundle and installer.
