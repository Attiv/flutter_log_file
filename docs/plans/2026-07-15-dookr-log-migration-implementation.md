# Dookr VLog Migration Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add backward-compatible filename templates to `flutter_log_file`, publish version 0.1.1, and migrate Dookr logging and its Option Page viewer to the package.

**Architecture:** `FileNamePolicy` remains the single authority for generating and recognizing managed log files, but renders a validated `LogConfig.fileNamePattern` stem before adding rotation parts and extensions. Dookr initializes the static `VLog` facade against its existing external log directory, calls it directly from business code, and opens `VLogViewerPage` from the retained diagnostic panel.

**Tech Stack:** Flutter 3.32, Dart 3.8, `flutter_log_file`, GetX, `flutter_test`, Gradle/Android debug build.

---

### Task 1: Create isolated worktrees and verify baselines

**Files:**
- Modify: `/Users/mac/projects/dookr-apk/.gitignore`

**Step 1: Ensure project-local worktrees are ignored**

Confirm `/Users/mac/github/flutter_log_file/.worktrees` is ignored. Add
`.worktrees/` to the Dookr `.gitignore`, verify with `git check-ignore`, and
commit only that ignore rule.

**Step 2: Create feature worktrees**

Create:

```bash
git worktree add .worktrees/file-name-pattern -b feat/file-name-pattern
git worktree add .worktrees/vlog-migration -b feat/vlog-migration
```

Run the first command in the library and the second in Dookr.

**Step 3: Verify baselines**

In the library worktree run:

```bash
flutter pub get
flutter test
```

Expected: all 106 existing tests pass.

In Dookr run:

```bash
flutter analyze lib
flutter test
```

Expected analyzer baseline: only the existing filename infos. The generated
`test/widget_test.dart` is known to fail because it imports the obsolete
`package:dookr_apk/main.dart` and references a removed `MyApp`; replace it with
feature tests in later tasks rather than treating it as a product regression.

### Task 2: Add filename-template configuration with TDD

**Files:**
- Modify: `test/model/log_config_test.dart`
- Modify: `test/storage/file_name_policy_test.dart`
- Modify: `lib/src/model/log_config.dart`
- Modify: `lib/src/storage/file_name_policy.dart`

**Step 1: Write failing configuration tests**

Assert that the default pattern is `{prefix}_{date}` and invalid patterns are
rejected: empty stems, path separators, missing `{date}` when `splitByDay` is
true, and `{date}` when `splitByDay` is false.

**Step 2: Write failing policy tests**

Add expectations equivalent to:

```dart
final policy = FileNamePolicy(LogConfig(
  fileNamePattern: '{date}-logFile',
  fileDatePattern: 'yyyyMMdd',
));

expect(policy.fileName(day), '20260715-logFile.txt');
expect(policy.fileName(day, part: 1), '20260715-logFile.1.txt');
expect(policy.parse('20260715-logFile.12.txt')?.date, DateTime(2026, 7, 15));
expect(policy.parse('20260715-logFile.12.txt')?.part, 12);
```

Also prove the existing default and non-daily names remain unchanged.

**Step 3: Verify RED**

Run:

```bash
flutter test test/model/log_config_test.dart test/storage/file_name_policy_test.dart
```

Expected: compilation/test failures because `fileNamePattern` does not exist.

**Step 4: Implement the minimum configuration and policy changes**

Add `fileNamePattern` with default `{prefix}_{date}`. Validate it as a filename
stem template. Build an anchored ownership regex by escaping literal segments
and replacing `{prefix}` and `{date}` with their escaped/capturing forms. Keep
the numeric part immediately before the extension.

**Step 5: Verify GREEN and refactor**

Run the focused tests, then:

```bash
dart format lib test
flutter analyze
flutter test
```

Expected: all tests pass with no analyzer issues.

**Step 6: Commit**

```bash
git add lib test
git commit -m "feat: support configurable log filename templates"
```

### Task 3: Document and version library 0.1.1

**Files:**
- Modify: `pubspec.yaml`
- Modify: `CHANGELOG.md`
- Modify: `README.md`
- Modify: `README_CN.md`

**Step 1: Document the public option**

Add the Dookr-compatible example and document supported tokens, validation,
daily-splitting interaction, and rotated names.

**Step 2: Set version 0.1.1**

Add a `0.1.1` changelog entry describing the backward-compatible filename
template feature.

**Step 3: Verify publication contents**

Run:

```bash
dart format --output=none --set-exit-if-changed lib test
flutter analyze
flutter test
flutter pub publish --dry-run
git diff --check
```

Expected: zero warnings and all tests pass.

**Step 4: Commit**

```bash
git add pubspec.yaml CHANGELOG.md README.md README_CN.md
git commit -m "docs: prepare 0.1.1 release"
```

### Task 4: Add Dookr dependency and tested VLog bootstrap

**Files:**
- Modify: `/Users/mac/projects/dookr-apk/pubspec.yaml`
- Modify: `/Users/mac/projects/dookr-apk/pubspec.lock`
- Create: `/Users/mac/projects/dookr-apk/lib/service/vlog_service.dart`
- Delete: `/Users/mac/projects/dookr-apk/test/widget_test.dart`
- Create: `/Users/mac/projects/dookr-apk/test/service/vlog_service_test.dart`

**Step 1: Point the feature worktree at the library worktree**

During development use a path dependency on the library feature worktree and
upgrade `intl` to `^0.20.2`. Set Dart/Flutter floors to 3.4/3.22.

**Step 2: Write a failing bootstrap test**

Test a pure `createDookrLogConfig(String directoryPath)` function. Assert the
old directory, `{date}-logFile`, `yyyyMMdd`, 15-day retention, error flushing,
and configured secret-key redaction.

**Step 3: Verify RED**

Run:

```bash
flutter test test/service/vlog_service_test.dart
```

Expected: failure because the bootstrap/config factory does not exist.

**Step 4: Implement bootstrap**

Create the configuration factory and an `initializeDookrLogging` function that
calls `VLog.init`. Do not install package-owned global handlers.

**Step 5: Verify GREEN and commit**

Run the focused test and `flutter analyze lib test`, then commit the dependency,
lockfile, bootstrap, and replacement of the obsolete generated test.

### Task 5: Replace custom Logger calls with direct VLog calls

**Files:**
- Modify: `/Users/mac/projects/dookr-apk/lib/main.dart`
- Modify all current importers of `service/logging_service.dart`
- Delete: `/Users/mac/projects/dookr-apk/lib/service/logging_service.dart`

**Step 1: Add a failing source regression test**

Create `test/service/logging_migration_test.dart` that scans `lib/` and fails if
production Dart files import `logging_service.dart`, instantiate/find `Logger`,
or call `logger.log`.

**Step 2: Verify RED**

Run the new test and confirm it reports the existing custom logger usages.

**Step 3: Migrate initialization and handlers**

Initialize VLog after `FileDownloadProvider`. Change Flutter/platform handlers
to `VLog.e` and preserve the platform handler's `true` result.

**Step 4: Migrate business calls**

Import `flutter_log_file` and use direct calls. Use `VLog.e` with structured
`error` and `stackTrace` where catch blocks already provide them, `VLog.w` for
recoverable validation/unsupported-input paths, and `VLog.i` for lifecycle and
successful operations. Preserve the existing QR-code masking.

**Step 5: Remove the old service**

Delete its GetX registration, imports, queue, timer, cleanup, writer, and tests.
Use `VLog.flush` at explicit durability boundaries.

**Step 6: Verify GREEN and commit**

Run the regression test and analyzer, review every changed log call, then
commit with `refactor: migrate logging to VLog`.

### Task 6: Replace Option Page inline reader with VLogViewerPage

**Files:**
- Modify: `/Users/mac/projects/dookr-apk/lib/page/home/OptionsPage.dart`
- Modify: `/Users/mac/projects/dookr-apk/lib/page/home/OptionsPageController.dart`
- Create: `/Users/mac/projects/dookr-apk/test/page/home/options_log_viewer_test.dart`

**Step 1: Write failing tests**

Test that the retained Logs & Status panel still exposes diagnostic controls
and that its Open Log Viewer action navigates to a `VLogViewerPage`. Add a
source-level regression assertion that custom reverse-chunk reader state and
methods are gone.

**Step 2: Verify RED**

Run the focused tests and confirm the viewer action is missing and old reader
code remains.

**Step 3: Implement the UI migration**

Keep diagnostic summary/actions. Remove log search, refresh/copy/clear/load-more
controls and the inline line list. Add an Open Log Viewer button using GetX
navigation. Read the directory from `VLog.logDirectoryPath` in the diagnostic
summary.

**Step 4: Verify GREEN and commit**

Run focused tests and analysis, then commit with
`refactor(options): use VLog viewer`.

### Task 7: Verify, publish, and integrate

**Files:**
- Modify: `/Users/mac/projects/dookr-apk/pubspec.yaml`
- Modify: `/Users/mac/projects/dookr-apk/pubspec.lock`

**Step 1: Verify library feature branch**

Run full format, analyze, tests, dry-run, and `git diff --check` fresh.

**Step 2: Publish 0.1.1**

Run `flutter pub publish --force`, complete OAuth if requested, and verify
version 0.1.1 using `https://pub.dev/api/packages/flutter_log_file`.

**Step 3: Switch Dookr to hosted dependency**

Replace the temporary path dependency with `flutter_log_file: ^0.1.1` and run
`flutter pub get`.

**Step 4: Verify Dookr**

Run:

```bash
dart format --output=none --set-exit-if-changed lib test
flutter analyze lib test
flutter test
flutter build apk --debug
git diff --check
```

Expected: tests and build pass; analyzer has no errors.

**Step 5: Commit hosted dependency resolution**

Commit only the hosted-dependency change if it was not already included.

**Step 6: Integrate feature branches**

Merge each verified feature branch into its original checked-out branch without
force operations. Re-run the focused smoke checks in the original working
directories, preserve Dookr's untracked PowerPoint file, and report commit IDs,
publication URL, test counts, analyzer result, and APK path.
