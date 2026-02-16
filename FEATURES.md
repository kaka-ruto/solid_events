# SolidEvents Feature Checklist

This file tracks the high-level behaviors `solid_events` should provide to make Rails observability story-first, queryable, and useful for humans + agents.

Reference framing: [loggingsucks.com](https://loggingsucks.com) (logs should answer questions, not just dump lines).

## Product goal

Turn Rails runtime signals into structured, queryable event data so teams can answer questions like:

- Why did a checkout fail?
- Are premium users experiencing more errors?
- Which deployment caused a latency regression?
- What is the error rate for the new checkout flow?

Important: these are outcome examples, not a requirement to build natural-language Q&A features into this gem.

## Non-goals

- `solid_events` is not a chat assistant or natural-language question-answering product.
- `solid_events` does not orchestrate or execute agent workflows (fixing code, creating PRs, browser QA).
- `solid_events` does not replace BI/analytics tools; it provides structured observability data those tools can consume.
- `solid_events` should avoid embedding team-specific automation policy; expose evidence cleanly instead.

## 1) Capture a full execution story

- [x] Capture request traces from `process_action.action_controller`
- [x] Capture job traces from `perform.active_job`
- [x] Capture SQL spans from `sql.active_record` with duration
- [x] Track trace lifecycle (`started_at`, `finished_at`, `status`)
- [x] Capture contextual metadata (`path`, method, status, request_id, queue)
- [x] Capture Action Cable / mailer / external HTTP spans as first-class events
- [x] Capture explicit causal links across async boundaries (request -> job chain)

## 2) Canonical wide-event model

- [x] Maintain one canonical summary row per trace (`solid_events_summaries`)
- [x] Include outcome, HTTP, timing, SQL, entity, and error dimensions
- [x] Include deploy/service dimensions (`service`, `env`, `version`, `deployment`, `region`)
- [x] Include schema version for stable consumer parsing
- [x] Support wide-event primary mode (optional sub-event suppression)
- [x] Materialize higher-level “story segments” (journey/session aggregates) as first-class records

## 3) Correlation and explainability

- [x] Auto-link mutated/created ActiveRecord records to traces
- [x] Link traces to `solid_errors` records via fingerprint + matching heuristics
- [x] Preserve error fingerprint on traces/summaries for grouping
- [x] Provide related-trace pivots by entity and fingerprint in UI
- [x] Persist per-step causal graph edges (event A caused event B) beyond trace-local ordering
- [x] Persist before/after business state diffs for key domain entities

## 4) Queryability for operator questions

- [x] Filter traces by time window, status, type, source, entity, request_id, fingerprint, context key/value
- [x] Compute and show latency percentiles and error rates in UI
- [x] Show hot paths and regression candidates from summary data
- [x] Show “new fingerprint” insights (including since deploy/version)
- [x] Built-in cohort analytics (e.g., premium vs non-premium) without custom SQL
- [x] Built-in feature-flag/experiment slice analytics without custom SQL
- [x] Built-in endpoint for “top failing user journeys” (multi-trace sequence view)

## 5) Incident state management (within observability scope)

- [x] Detect incidents for new fingerprints, error spikes, and p95 regressions
- [x] Deduplicate incidents in a configurable window
- [x] Support lifecycle transitions: acknowledge, resolve, reopen
- [x] Support assignment/muting metadata on incidents
- [x] Auto-resolve recovered incidents after quiet period
- [x] Retention tiers for success traces, error traces, incidents
- [x] SLO burn-rate style incident detection
- [x] Multi-signal incident policies (error + latency + saturation in one rule)

## 6) API exposure (data plane for humans/agents/tools)

- [x] Expose traces API and incident APIs
- [x] Expose incident context/evidence payloads
- [x] Support API token auth for `/solid_events/api/*`
- [x] Keep APIs observability-only (no automation/executor responsibilities)
- [x] Provide comparative metrics API for window-over-window regression checks
- [x] Versioned/public API contract document with compatibility guarantees
- [x] Cursor pagination for large result sets
- [x] Prebuilt aggregate endpoints (error rates + latency aggregates by key dimensions)
- [x] JSON export endpoints for traces/incidents with filter context

## 7) Signal quality, noise reduction, and safety

- [x] Ignore noisy internal namespaces by default (solid_*, ActiveStorage, etc.)
- [x] Allow override/re-enable through allowlists
- [x] Tail sampling (always keep failures/slow traces, sample low-value success traffic)
- [x] Redact sensitive keys in context/payload before persistence/log emission
- [x] Emit canonical JSON log line per sampled trace for log pipeline compatibility
- [x] Configurable PII policies per field path (not just key-name matching)
- [x] Optional payload truncation/size guards with visibility counters

## 8) UI workflows for investigations

- [x] Trace index with rich filters and pagination
- [x] Trace show page with canonical event, context, waterfall, record links, error links
- [x] Incident feed with lifecycle actions
- [x] Dedicated incident lifecycle history page in UI
- [x] Hot-path drilldown with percentile/error buckets
- [x] Journey sequences panel with request/entity grouping and quick links
- [x] Journey views support failing-only mode for focused incident triage
- [x] Incident shortcuts to open related journey views quickly
- [x] Saved views / shareable investigation links
- [x] UI compare mode (release A vs release B, cohort A vs cohort B)
- [x] Timeline view optimized for “tell me what happened” narratives
- [x] Timeline includes incident lifecycle markers for richer narrative context

## 9) Agent-readiness (observability side only)

- [x] Stable canonical event payload for machine consumers
- [x] Incident context endpoint returns evidence + suggested filters
- [x] Data model separates observability state from automation execution concerns
- [x] Additional aggregate/analysis APIs that provide reusable evidence slices (without embedding agent orchestration here)

## 10) Operational readiness

- [x] Install generator + isolated DB schema support
- [x] Background jobs/tasks for incident evaluation and pruning
- [x] Minitest coverage across tracer/subscribers/API/controllers/jobs
- [x] Load/perf benchmark suite with throughput targets
- [x] Migration guide for teams replacing default log-centric workflows

---

## Current focus

To align with the “Rails can already answer these questions” goal, the next major gap is:

1. Expose materialized journey and causal-edge records through dedicated APIs for bulk consumers
2. Add higher-fidelity business state transition controls for selected entity classes
3. Extend migration/performance guidance for production rollouts at scale
