## 0.1.2

* Default Android logs to the app's external files directory and migrate owned
  logs from the old Support/logs directory without overwriting existing files.
  Custom paths still take precedence; `useExternalStorageOnAndroid: false`
  retains internal storage.
* Add `VLog.exportLogsToDownloads` and viewer actions for all or selected logs.
  Android 10+ writes a ZIP directly to public Downloads; older Android versions
  use the system save picker. No broad storage permission is required.
* Handle export progress, cancellation and errors inside the plugin.
* Fix log-row Material compatibility and await byte reads before closing files.

## 0.1.1

* Add validated filename stem templates with `{prefix}` and `{date}` tokens.
* Support compact `yyyyMMdd` dates for legacy-compatible managed filenames.

## 0.1.0

* Add the `VLog` console and rotating file logging API.
* Add Android and Windows App Support directory resolution.
* Add configurable JSON/object formatting, optional error capture and opt-in redaction.
* Add bounded-memory lazy viewer pages and isolate-backed search.
* Use English for all bundled runtime UI and demo messages.
* Bound queued log memory by retained bytes and snapshot application values.
* Bound tail decoding during large-file viewing and reduce search allocation churn.
