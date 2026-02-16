# Changelog

All notable changes to this project are documented in this file.

## [0.2.0] - 2026-02-16

- Expanded tracing beyond controller/job/SQL into Action Cable, mailer, and external HTTP spans with async causal links across request/job chains.
- Established canonical wide-event summaries (`solid_events_summaries`) with schema versioning, HTTP/timing/SQL/error/entity dimensions, and deploy/service metadata.
- Added journey/session story modeling with first-class journey records and timeline-focused narrative support.
- Improved correlation and explainability with record links, state diffs, causal edges, fingerprint grouping, and Solid Errors linking heuristics.
- Added incident management for observability use cases: detection (new fingerprints, spikes, p95, SLO burn), dedupe windows, lifecycle transitions, assignment/muting, and auto-recovery.
- Shipped observability APIs with token auth, cursor pagination, comparative metrics, aggregate endpoints, incident evidence/context payloads, and JSON exports.
- Upgraded investigation UI with richer trace filters, trace details, hot-path/regression views, saved views, compare mode, incident lifecycle pages, and journey drilldowns.
- Added signal-quality controls: default noise suppression for internal namespaces, allowlist overrides, tail sampling, context/payload redaction policies, truncation guards, and canonical JSON log emission.
- Added operational support: isolated DB install flow, pruning/evaluation jobs, benchmark utilities, and expanded Minitest coverage across tracer/subscribers/API/controllers/jobs.
- Fixed summary availability checks to avoid sticky false caching when the summaries table is temporarily unavailable, so subsequent traces can create canonical summaries once storage is ready.
- Fixed summary consistency by ensuring all error-link attachment paths (including reconciliation flows) refresh the trace summary, keeping `summary.error_count` aligned with persisted error links.
- Added tracer regressions for summary-availability retry behavior and summary error-count synchronization after reconciliation.
- Updated ignored generated test artifacts to exclude additional dummy SQLite output under `test/dummy/storage`.
- Updated development lockfile metadata for Ruby `4.0.1`.

## [0.1.0] - 2026-02-16

- Initial release of `solid_events`.
- Added Rails engine install generator and schema setup.
- Added request, SQL, and Active Job tracing.
- Added record linking and Solid Errors linking.
- Added trace dashboard UI with filtering, pagination, and trace details.
- Added configuration for ignore rules, retention, and DB connection selection.
