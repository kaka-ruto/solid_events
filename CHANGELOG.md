# Changelog

All notable changes to this project are documented in this file.

## [v0.2.4] - 2026-03-11

- Switched installer guidance to schema-first events setup (`db/events_schema.rb`) to match solid_errors-style deployment flow.
- Removed migration-copy install flow from generator/tasks to avoid schema + replay drift in app installs.

## [v0.2.3] - 2026-03-11

- Aligned installer/task conventions with sibling Solid gems: use `events` database key, `db/events_schema.rb`, and `db/events_migrate`.
- Kept v0.2.2 migration idempotency fixes for schema-first `db:prepare` workflows.

## [v0.2.2] - 2026-03-11

- Fixed installer production config to use `config.solid_events.connects_to = { database: { writing: :events } }` so generated config matches common `database.yml` naming.
- Made installer-copied event migrations idempotent (`column_exists?`/`index_exists?`/`table_exists?` guards) to prevent duplicate table/column/index failures when `db:prepare` loads `db/events_schema.rb` before migrations.

## [v0.2.1] - 2026-03-04

- Added GitHub CI workflow to run the test suite on push/pull request.
- Fixed dummy test app bootstrapping by disabling `maintain_test_schema` to prevent pending-migration failures in clean test runs.
- Improved local release workflow compatibility by adding a repo-level `cleo.yml`.
- Added QA bootstrap files (`.github/pull_request_template.md` and `.github/workflows/qa.yml`) for consistent quality workflow setup.
- Updated README formatting by removing emoji-prefixed headings and feature bullets.
- Updated gem version to `0.2.1`.

## [v0.2.0] - 2026-02-16

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

## [v0.1.0] - 2026-02-16

- Initial release of `solid_events`.
- Added Rails engine install generator and schema setup.
- Added request, SQL, and Active Job tracing.
- Added record linking and Solid Errors linking.
- Added trace dashboard UI with filtering, pagination, and trace details.
- Added configuration for ignore rules, retention, and DB connection selection.
