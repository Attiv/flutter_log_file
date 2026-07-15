# VLog Memory Audit

Audit date: 2026-07-15

## Logging pipeline

- The asynchronous queue is bounded by both entry count and estimated retained serialized bytes.
- Defaults: `queueCapacity = 10000`, `queueByteCapacity = 8 MB`.
- Active and pending entries are both included in the retained-byte budget.
- Messages, fields, errors, stack traces, and tags are snapshotted before enqueueing. The queue does not retain the original application object graph.
- Normalization is bounded by node count, character count, and recursion depth. Infinite or extremely large iterables cannot be normalized without a limit.
- Calls made before `VLog.init()` use a separate bounded snapshot buffer: at most 1,000 entries and approximately 2 MB of serialized data.
- Individual retained components remain limited by `maxEntryBytes`, which defaults to 256 KB.

## File viewer

- Files are read in 128 KB chunks by default and are never loaded completely into memory.
- The decoded viewer window defaults to 4 MB.
- Initial tail decoding applies the byte budget while parsing, avoiding a large temporary list before controller trimming.
- A physical line is decoded up to `maximumLineBytes`, which defaults to 1 MB. The remaining bytes are scanned without being retained.
- Decoded byte accounting is cached and updated incrementally rather than rescanning the complete window during every trim.
- Live-write stream subscriptions, scroll/text controllers, and search subscriptions are cancelled or disposed with their pages.

## Search

- Search runs in a dedicated isolate and reads 128 KB chunks.
- Buffered physical line data is capped at 1 MB.
- Results default to at most 5,000 entries and snippets default to at most 500 characters.
- Incremental result delivery appends in place instead of copying the complete result list for every match.
- Cancellation kills the search isolate, closes the receive port, and closes result/progress streams.

## Remaining considerations

- Byte budgets represent serialized data, not exact Dart heap size. Strings, maps, object headers, and VM bookkeeping add overhead.
- Setting very high queue, entry, viewer, or search limits increases memory use by design.
- Disabling retention and configuring very small rotation sizes can create a very large number of files; file metadata operations scale with that file count.
- The operating system and Dart VM may retain file-system cache or heap pages after objects are released. This is not an application-level reference leak.
