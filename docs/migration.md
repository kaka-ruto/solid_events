# Migrating from Rails Log Files to SolidEvents

This guide helps teams move from line-based Rails logs to `solid_events` as the primary investigation surface.

## 1) Install and isolate storage

1. Add gem and run installer.
2. Configure dedicated database connection (`config.solid_events.connects_to`) for write isolation.
3. Run migrations.

## 2) Start with canonical summaries

1. Keep default instrumentation on (controller, job, sql).
2. Enable summary-first workflows in UI:
   - traces
   - compare
   - journeys
   - timeline
3. Keep Rails logs enabled during rollout.

## 3) Tune signal quality

1. Add namespace/model/path ignores to remove framework noise.
2. Configure redaction:
   - `sensitive_keys`
   - `redaction_paths`
3. Set payload guard limits:
   - `max_context_payload_bytes`
   - `max_event_payload_bytes`

## 4) Operationalize incident workflows

1. Enable incident evaluator job cadence.
2. Use incident lifecycle actions (ack/resolve/reopen/assign/mute).
3. Review lifecycle history via:
   - UI incident lifecycle column
   - `GET /solid_events/api/incidents/:id/events`

## 5) Replace common log-driven workflows

- “Find latest failures” -> Incident feed + traces filtered by status/error fingerprint.
- “Compare before/after deploy” -> Compare panel and metrics compare API.
- “Reconstruct what happened” -> Journey panel + Timeline view.
- “Share investigation state” -> Saved views and immutable shared links.

## 6) Validate performance baseline

Run:

```bash
bundle exec rake "solid_events:benchmark[200]"
```

Use `docs/performance.md` targets as rollout guardrails.

## 7) Roll out bulk-consumer APIs safely

Use staged rollout for the new high-volume APIs:

1. Validate in staging:
   - `GET /solid_events/api/journeys/materialized?limit=50`
   - `GET /solid_events/api/causal_edges?limit=50`
2. Start with a low polling cadence in production (30-60s) for external consumers.
3. Add API token auth before enabling external agents on these endpoints.

## 8) Roll out state-diff capture by domain

Avoid enabling full-model diff capture everywhere on day one.

1. Start with explicit allowlist:
   - `config.state_diff_allowlist = ["Order", "Subscription"]`
2. Cap payload growth:
   - `config.state_diff_max_changed_fields = 20`
3. Exclude noisy models:
   - `config.state_diff_blocklist = ["Ahoy::Event", "PaperTrail::Version"]`
4. Expand allowlist only after measuring storage growth and query latency.

## 9) Post-rollout checks

After 24-48 hours in production, verify:

- Incident evaluation job runtime and queue latency
- `solid_events_summaries` growth vs retention windows
- `solid_events_journeys` and `solid_events_causal_edges` query latency
- API consumer cursor usage (no offset-based polling)
