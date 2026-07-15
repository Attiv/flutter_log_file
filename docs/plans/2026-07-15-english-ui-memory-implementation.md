# English Runtime UI and Memory Hardening Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Convert all VLog package/demo runtime text to English and add hard memory bounds for asynchronous logging and large-file viewing.

**Architecture:** Keep public logging and viewer APIs stable while adding `queueByteCapacity` to `LogConfig`. Snapshot application values into normalized bounded data before enqueueing, extend the generic serial queue with optional retained-weight accounting, and enforce the viewer budget while decoding rather than only after a chunk is created.

**Tech Stack:** Dart, Flutter Material 3, `dart:io`, isolates, `flutter_test`.

---

### Task 1: Translate package and demo runtime strings

**Files:**
- Modify: `lib/src/viewer/log_viewer_page.dart`
- Modify: `lib/src/viewer/log_file_page.dart`
- Modify: `example/lib/demo_app.dart`
- Modify: `example/lib/demo_home_page.dart`
- Modify: `example/README.md`
- Modify: viewer and demo widget tests

Write/update widget expectations first, verify they fail against Chinese labels, replace all runtime strings, force English date picker/demo locale, and rerun focused tests.

### Task 2: Add retained-byte limits to the serial queue

**Files:**
- Modify: `lib/src/core/log_queue.dart`
- Modify: `lib/src/model/log_config.dart`
- Test: `test/core/log_queue_test.dart`
- Test: `test/model/log_config_test.dart`

Add failing tests for active-plus-pending byte limits and invalid configuration. Implement optional queue weight accounting and configurable `queueByteCapacity`, then rerun focused tests.

### Task 3: Snapshot and bound queued log values

**Files:**
- Modify: `lib/src/core/log_controller.dart`
- Modify: `lib/src/model/log_entry.dart`
- Test: `test/core/log_controller_test.dart`

Add failing tests showing original object graphs and mutable nested fields are not retained. Normalize/copy values at the log call site, truncate each retained component, estimate retained bytes, and pass weights to the queue.

### Task 4: Bound viewer intermediate memory and remove allocation churn

**Files:**
- Modify: `lib/src/viewer/file_chunk_reader.dart`
- Modify: `lib/src/viewer/log_file_controller.dart`
- Modify: `lib/src/viewer/log_file_page.dart`
- Test: `test/viewer/file_chunk_reader_test.dart`
- Test: `test/viewer/log_file_controller_test.dart`

Add failing large-line tail tests, enforce a byte budget during tail decoding, cache controller byte counts, remove unconditional byte-list copies, and append search results without copying the full list.

### Task 5: Full verification and delivery

Run formatting, root/example analysis and tests, Android debug build, package dry-run, runtime Chinese-string audit, Git checks, commit, and push `main`.
