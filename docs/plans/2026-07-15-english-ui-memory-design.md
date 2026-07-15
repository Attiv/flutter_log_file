# English Runtime UI and Memory Hardening Design

## Goal

Make every runtime-facing string in the VLog package and demo English, then harden the logger and bundled viewer against avoidable memory retention and transient allocation spikes.

## Runtime language scope

The bundled file list, file reader, search/filter sheets, copy actions, dialogs, tooltips, errors, empty states, demo controls, snackbars, dialogs, and sample log payloads will use English. The demo app will force an English Material locale, and the viewer's date-range picker will explicitly request English so it remains English inside a non-English host app.

Documentation language files remain intentional: `README.md` stays English and `README_CN.md` stays Chinese. Test fixtures may continue to contain non-English Unicode where they validate UTF-8 behavior rather than display application text.

## Memory findings and changes

1. The queue is bounded by entry count but not by retained bytes. A queue containing many maximum-sized entries can retain far more memory than expected. Add a configurable total queue byte budget and make the serial queue reject/drop pending entries before the active-plus-pending retained weight exceeds that budget.
2. Log entries currently retain original message and field object graphs until asynchronous sinks process them. Normalize and snapshot messages, fields, errors, and stack traces at the call site, while preserving compact/pretty sink formatting and applying size limits.
3. Tail loading limits the number of lines before the controller trims to its memory budget. Many individually large lines can therefore create a large transient list. Add a byte limit during tail decoding so the oversized intermediate window is never retained.
4. Search UI appends each result by copying the complete result list. Replace this with in-place bounded accumulation to eliminate quadratic transient allocation.
5. Viewer byte accounting is recalculated across the full line window during every trim iteration. Maintain cached byte accounting to avoid repeated scans and temporary CPU pressure.
6. Line decoding makes an unconditional copy of every byte list. Decode the existing bounded buffer directly and copy only when removing a trailing carriage return.

## Verification

- Translation tests assert the public viewer and demo expose English labels and messages.
- Queue tests cover count and byte budgets, including an active item plus pending items.
- Controller tests prove queued values are normalized snapshots rather than references to application objects.
- Reader/controller stress tests prove tail and decoded windows remain within configured budgets for large lines.
- Search tests retain the existing result limit and cancellation coverage.
- Root and example analysis/tests, Android debug build, package dry-run, and Git whitespace checks must pass.
