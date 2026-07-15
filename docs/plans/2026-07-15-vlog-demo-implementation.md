# VLog Demo App Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add a runnable Material 3 Flutter demo under `example/` that lets developers exercise VLog configuration, log levels, structured values, errors, and the lazy viewer.

**Architecture:** Build a standard Flutter app in `example/` using the parent package through a path dependency. Keep the demo UI and sample model code separate, initialize VLog once in `main.dart`, and navigate to the package-provided `VLogViewerPage` instead of duplicating viewer logic.

**Tech Stack:** Flutter, Dart, Material 3, `flutter_test`, `flutter_log_file` path dependency.

---

### Task 1: Scaffold the example Flutter application

**Files:**
- Create/update: `example/pubspec.yaml`
- Create: generated `example/android/` and `example/windows/` platform files
- Create: `example/lib/main.dart`

**Step 1: Generate the Flutter app shell**

Run `flutter create --project-name vlog_demo --platforms=android,windows example` and preserve the existing `example/README.md` content where practical.

**Step 2: Configure the path dependency**

Add `flutter_log_file: path: ..` to `example/pubspec.yaml` and remove generated counter-app dependencies/assets that are not used.

**Step 3: Write the app entry point**

Initialize Flutter bindings, initialize VLog with demo defaults, and call `runApp(const DemoApp())`.

**Step 4: Resolve dependencies**

Run `flutter pub get` from `example/` and confirm the parent package resolves through the local path.

### Task 2: Add sample models and Material 3 app shell

**Files:**
- Create: `example/lib/demo_models.dart`
- Create: `example/lib/demo_app.dart`

**Step 1: Write the model test**

Add a test asserting `DemoUser.toJson()` returns stable structured fields.

**Step 2: Run the focused test and verify it fails**

Run `flutter test test/demo_models_test.dart` from `example/`; it should fail because the model does not exist yet.

**Step 3: Implement the model and app shell**

Add `DemoUser`, a Material 3 theme, and a `DemoApp` route to `DemoHomePage`.

**Step 4: Run the focused test**

Run `flutter test test/demo_models_test.dart`; it should pass.

### Task 3: Implement the demo home page and logging controls

**Files:**
- Create: `example/lib/demo_home_page.dart`
- Create: `example/test/demo_home_page_test.dart`

**Step 1: Write failing widget tests**

Cover visible configuration controls, each log action, applying configuration, and opening the viewer route. Use a temporary directory configuration in tests so no host-global location is required.

**Step 2: Run the focused widget tests and verify the expected failures**

Run `flutter test test/demo_home_page_test.dart` from `example/`.

**Step 3: Implement the page**

Add responsive Material 3 cards for status/configuration/playground, level buttons, optional tag/message inputs, sample structured/error actions, configuration reinitialization, and a button that pushes `VLogViewerPage`.

**Step 4: Run focused tests and fix only implementation issues**

Run `flutter test test/demo_home_page_test.dart` until all focused tests pass.

### Task 4: Document and verify the demo

**Files:**
- Update: `example/README.md`

**Step 1: Document run commands and feature tour**

Explain `flutter pub get`, `flutter run -d windows`, `flutter run -d <android-device>`, the demo controls, and how to open the viewer.

**Step 2: Run package and demo verification**

Run `flutter analyze` and `flutter test` from both the repository root and `example/`. Run `flutter pub publish --dry-run` from the repository root to ensure the example remains publishable.

**Step 3: Review the diff and commit**

Run `git diff --check`, stage only demo/design/plan files, and commit with `feat(example): add VLog demo app`.
