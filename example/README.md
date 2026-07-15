# VLog Material 3 Demo

This is the complete Android and Windows demo for `flutter_log_file`. It uses a local path dependency on the parent package, so publishing to pub.dev is not required.

## Run

```bash
cd example
flutter pub get
```

Android:

```bash
flutter devices
flutter run -d <android-device-id>
```

Windows:

```bash
flutter run -d windows
```

## What you can try

### Output configuration

- Enable or disable console and file output independently;
- Show or hide tags;
- Enable or disable pretty JSON;
- Split log files by day;
- Change the log filename prefix;
- Enable ANSI console colors;
- Select the minimum log level;
- Apply changes by creating a new VLog session.

### Log playground

- Enter any message and an optional tag;
- Write Verbose, Debug, Info, Warning, Error, and Fatal entries;
- Write nested Map/List JSON;
- Write a `DemoUser` through `toJson()`;
- Write a `DemoOrder` through a registered encoder;
- Write an error, stack trace, and structured fields;
- Generate 200 entries at once to exercise lazy loading and search.

### Log viewer

Select **View logs** in the app bar or **Open log viewer** in the playground to open the package-provided `VLogViewerPage`. The viewer supports:

- File size and active-file status;
- Lazy loading from the end of a file;
- Live follow and pause;
- Keyword, regex, level, tag, and date filters;
- Isolate-based streaming search and result navigation;
- Copy, share, delete, and expired-log cleanup actions.

## Test

```bash
cd example
flutter analyze
flutter test
```

Widget tests use a temporary directory and do not depend on Android or Windows directory plugins.
