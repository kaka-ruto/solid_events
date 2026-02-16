# SolidEvents API Contract

This document defines the public API contract for `solid_events` engine endpoints.

## Versioning policy

- Current version: `v1`
- Versioning model:
  - Backward-compatible additions (new optional params, new response fields) are allowed in `v1`.
  - Breaking changes require a new versioned path (`/solid_events/api/v2/...`) and migration notes.
- Canonical event payloads include `schema_version` for machine consumers.

## Auth

- Optional token auth can protect all `/solid_events/api/*` endpoints.
- Configure with `config.api_token` or `SOLID_EVENTS_API_TOKEN`.
- Accepted headers:
  - `X-Solid-Events-Token: <token>`
  - `Authorization: Bearer <token>`

## Response envelopes

- List endpoints return:
  - `{ data: [...], next_cursor: <id|null> }` for cursor pagination, or
  - endpoint-specific list payloads (for metrics/journeys), documented below.
- Detail endpoints return endpoint-specific objects.
- Errors return:
  - `{ error: "..." }` with relevant HTTP status.

## Common query params

- `limit` (default `50`, max `200`)
- `cursor` for descending id pagination on supported endpoints
- `window` one of: `1h`, `24h`, `7d`, `30d` (endpoint-dependent default `24h`)
- Feature slice filtering (where supported):
  - `feature_key`
  - `feature_value`

## Endpoints

### Incidents

- `GET /solid_events/api/incidents`
  - Filters: `status`, `kind`, `severity`, `limit`, `cursor`
  - Response: `{ data: [incident...], next_cursor: Integer|null }`

- `GET /solid_events/api/incidents/:id/traces`
  - Response: `{ incident: {...}, traces: [canonical_trace...] }`

- `GET /solid_events/api/incidents/:id/context`
  - Response includes incident details, evidence traces/errors, and suggested links.

- `GET /solid_events/api/incidents/:id/events`
  - Filters: `event_action`, `limit`, `cursor`
  - Response: `{ incident: {...}, data: [incident_event...], next_cursor: Integer|null }`

- `GET /solid_events/api/incidents/:id/evidence_slices`
  - Response: aggregate slices for source/status/entity, duration stats, and error rate.

- `PATCH /solid_events/api/incidents/:id/acknowledge`
- `PATCH /solid_events/api/incidents/:id/resolve`
  - Optional body params: `resolved_by`, `resolution_note`
- `PATCH /solid_events/api/incidents/:id/reopen`
- `PATCH /solid_events/api/incidents/:id/assign`
  - Params: `owner`, `team`, `assigned_by`, `assignment_note`
- `PATCH /solid_events/api/incidents/:id/mute`
  - Params: `minutes`

Incident kinds currently emitted by built-in evaluators:
- `new_fingerprint`
- `error_spike`
- `p95_regression`
- `slo_burn_rate`
- `multi_signal_degradation`

### Traces

- `GET /solid_events/api/traces`
  - Filters:
    - `error_fingerprint`
    - `entity_type`, `entity_id`
    - `feature_key`, `feature_value`
    - `limit`, `cursor`
  - Response: `{ data: [canonical_trace...], next_cursor: Integer|null }`

- `GET /solid_events/api/traces/:id`
  - Response:
    - `trace` canonical event
    - `summary`
    - `record_links`
    - `error_links`

### Metrics

- `GET /solid_events/api/metrics/error_rates`
  - Params: `dimension`, `window`, `feature_key`, `feature_value`
  - Response: `{ window, dimension, groups: [...] }`

- `GET /solid_events/api/metrics/latency`
  - Params: `dimension`, `window`, `feature_key`, `feature_value`
  - Response: `{ window, dimension, groups: [...] }`

- `GET /solid_events/api/metrics/compare`
  - Params: `metric`, `dimension`, `window`, `baseline_window`, `feature_key`, `feature_value`
  - Response: `{ metric, dimension, current_window, baseline_window, groups: [...] }`

- `GET /solid_events/api/metrics/cohorts`
  - Params: `cohort_key` (required), `cohort_values`, `metric`, `window`, `feature_key`, `feature_value`
  - Response: `{ window, cohort_key, metric, groups: [...] }`

### Journeys

- `GET /solid_events/api/journeys`
  - Filters:
    - `request_id`, or
    - `entity_type` + `entity_id`
    - `errors_only`
    - `window`
    - `traces_per_journey`
    - `limit`
  - Response: `{ window, errors_only, journeys: [...] }`

### Exports (JSON only)

- `GET /solid_events/api/export/traces`
  - Supported params:
    - `format=json` (required for explicit export mode)
    - `status`
    - `error_fingerprint`
    - `entity_type`, `entity_id`
    - `feature_key`, `feature_value`
    - `window`
    - `limit`, `cursor`
  - Response:
    - `{ exported_at, format: "json", filters: {...}, data: [canonical_trace...] }`

- `GET /solid_events/api/export/incidents`
  - Supported params:
    - `format=json`
    - `status`, `kind`, `severity`
    - `window`
    - `limit`, `cursor`
  - Response:
    - `{ exported_at, format: "json", filters: {...}, data: [incident...] }`

## Stability guidance for consumers

- Prefer canonical fields from summaries/canonical events over raw event payload internals.
- Treat unknown fields as additive.
- Use `schema_version` defensively for parsing upgrades.
