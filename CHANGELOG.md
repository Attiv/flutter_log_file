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
