# VLog Demo App Design

## Goal

Add a complete Material 3 Flutter application under `example/` so developers can run the package and exercise its logging and viewer features on Android or Windows.

## User experience

The demo opens on a single `DemoHomePage` with a compact configuration panel and a log playground. Developers can toggle console/file output, tags, pretty JSON, daily splitting, and choose a file prefix before applying a new `LogConfig`. The playground provides buttons for each VLog level plus representative string, JSON, object, multiline JSON, and error entries. A prominent action opens the package's `VLogViewerPage`.

The UI uses Material 3 components, responsive single-column/two-column layout based on available width, cards for grouped controls, snackbars for operation results, and a status card showing initialization state and the active log directory.

## Architecture

- `example/lib/main.dart` initializes Flutter bindings, calls `VLog.init` with demo defaults, and starts the app.
- `example/lib/demo_app.dart` owns the `MaterialApp` theme and routes.
- `example/lib/demo_home_page.dart` owns editable controls and emits sample logs.
- `example/lib/demo_models.dart` defines a serializable `DemoUser` and order sample used to demonstrate registered encoders and `toJson()` behavior.
- The viewer is embedded directly through the package's public `VLogViewerPage`; no duplicate viewer implementation is added.
- `example/pubspec.yaml` depends on the parent package through `path: ..` and contains only the dependencies needed by the generated Flutter app.

## Error handling and lifecycle

The demo keeps global error capture disabled by default so it demonstrates the package's opt-in behavior. Re-initializing applies the current form values after flushing/closing the previous session. The app flushes and closes VLog from lifecycle hooks where appropriate; normal log calls remain fire-and-forget.

## Verification

- Widget tests cover the home page rendering, level buttons, JSON/object/error actions, configuration application, and viewer navigation.
- `flutter analyze` and `flutter test` run from `example/`.
- The package itself remains unchanged except for documentation/example integration files.
