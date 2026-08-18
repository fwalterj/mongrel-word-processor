Mongrel Dictionary Companion Package
===================================

This package mirrors the app's offline reference pool for companion writing tools.

Counts
------
- Structured entries: 546
- Search headwords: 529414
- Reference notes: 520

Files
-----
- manifest.json
  Build metadata and corpus counts.
- structured_entries.json
  Full structured reference material for app integrations, scripting, or downstream transforms.
- structured_entries.tsv
  Spreadsheet-friendly export of the same structured entries.
- headword_pool.txt
  One headword per line. Useful for custom lookup pools and term pickers.
- headword_pool.tsv
  Spreadsheet-friendly headword list with a flag for whether a term already has a structured reference note.
- spellcheck_dictionary.txt
  Plain newline dictionary for companion apps that support custom spelling imports.

Suggested use
-------------
- Import spellcheck_dictionary.txt into writing tools that accept plain-word custom dictionaries.
- Use structured_entries.tsv for quick filtering, sorting, and editorial review.
- Use structured_entries.json when a tool needs richer fields like chips, counterparts, and related terms.

Generated
---------
- UTC timestamp: 2026-05-04T14:46:14.458914+00:00
