# Mongrel Word Processor QA and Release Checklist

## Scope
- Validate document lifecycle reliability and truthful action behavior:
  - New/Open/Reopen/Close
  - Save/Save As/Export
  - Unsaved-change prompts and dirty-state indicator
  - Recovery behavior for stale last-document bookmarks
  - Workflow audit logging coverage

## Preflight
- [ ] Build succeeds for `MongrelWordProcessor` in Release configuration.
- [ ] App launches without runtime warnings or crashes.
- [ ] Menu command enable/disable states are accurate.
- [ ] Keyboard shortcuts trigger intended actions.

## Document Lifecycle
- [ ] `New Document` prompts when unsaved changes exist and follows Save/Discard/Cancel correctly.
- [ ] `Open...` prompts when unsaved changes exist and opens valid files.
- [ ] `Reopen Last Document` restores last document when available.
- [ ] Stale/invalid reopen bookmark is handled gracefully and clears invalid persisted reference.
- [ ] `Close Document` clears content/title/current path and resets dirty state.

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

## Logging and Diagnostics
- [ ] Workflow events are logged for open/reopen/new/close/save/export operations.
- [ ] Failure events include useful metadata for triage.

## Regression Pass
- [ ] Toolbar actions still map exactly to session methods.
- [ ] Command menu and toolbar remain behaviorally consistent.
- [ ] Text editor remains editable with undo and no rendering regressions.
