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
