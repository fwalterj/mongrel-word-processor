# Editor interaction rules

These are the behaviors implemented and checked for confident build 1.0.0 (4). They give future changes a concrete contract.

## Viewing and formatting

- View zoom is a display preference shared by the workspace. It does not alter saved font sizes or screenplay print geometry.
- Prose and wrapped source reflow to the visible width at every zoom level. Unwrapped source remains horizontally scrollable. Turning wrapping on returns the horizontal position to the left edge.
- Geometry changes preserve the selection. A visible caret anchors the vertical position; when the selection is offscreen, the first visible text anchors it instead. At document boundaries, scrolling is clamped to the available document.
- Screenplay uses fixed US Letter layout. Automatic Fit Width and manual zoom change the display scale. A manual zoom step from Fit Width starts at the current visible scale.
- Formatting controls act on the editor selection and return focus there. Text-size buttons change selected font runs by one point while preserving family and traits; without a selection, they change the typing font. Zoom remains a separate operation.
- A formatting undo restores formatting without removing the previous typing operation. Typing after undo starts a new history branch.

## Screenplay paste and semantics

| Input/action | Behavior |
|---|---|
| Native screenplay copy or cut | Preserve element metadata. A copied scene receives a fresh identity when the original remains in the document; a cut scene retains its identity. |
| Ordinary external text or rich-text paste | Use the destination screenplay element for the inserted paragraphs. Remove external paragraph geometry, font size/family, and background highlights. Preserve inline emphasis where the screenplay element supports it. |
| Paste as plain text | Use destination semantics without rich-text emphasis. |
| Screenplay → Paste and Parse Screenplay | Interpret plain text as screenplay structure without changing its words. |
| Auto Format | Re-evaluate the document while preserving explicit element choices. |

An assigned screenplay element takes precedence over text patterns in scene navigation and catalogs. A line beginning with `INT.` inside Dialogue remains dialogue. Untagged imported text can still be recognized by its scene-heading syntax.

## Recovery and file access

Named files retain a saved access bookmark. Recovery activates that grant before checking whether the file exists, comparing its disk identity, or reloading it; snapshot creation activates the grant while saving the bookmark. Dirty drafts remain attached when the backing file is unchanged, and become recovered copies when it is missing, unreadable, or conflicting. File-access behavior must also be tested in the sandboxed app through the native file picker, because an unrestricted test harness cannot reproduce every access failure.

## Validation

`Scripts/run-native-checks.sh` exercises the repository's native test bodies when the Xcode test runner is unavailable. Interaction coverage uses real TextKit 2 editors and native windows, including selection anchors, mixed-mode recovery, clipboard data, undo/redo, and screenplay pagination. Live app testing is also necessary: a direct clipboard-reader check did not reveal that native Paste could take another AppKit path.

Release evidence and outstanding platform limits are recorded in `QA_RELEASE_CHECKLIST.md` and the packaged `VALIDATION.md`. Intel is cross-compiled; a physical Intel Mac and older supported macOS versions still need runtime testing.
