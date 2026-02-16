# SolidEvents Performance Baseline

This baseline defines the initial query-performance targets for local/prod sanity checks.

## Benchmark command

```bash
bundle exec rake "solid_events:benchmark[200]"
bundle exec rake "solid_events:benchmark_check[200,150,250]"
```

## Initial targets

- `elapsed_ms <= 150` for sample size `200` on a typical developer machine
- `elapsed_ms <= 80` for sample size `200` on production-grade database hardware
- Repeatability target: three runs should stay within `+/-20%`

## Notes

- This benchmark is query-focused (read path) and does not measure ingestion throughput.
- Use this as a regression guard when adding indexes, filters, or timeline/metrics features.

## Incident event query planning

To keep timeline and lifecycle APIs fast, ensure these indexes exist:

- `index_solid_events_incident_events_on_incident_and_time`
- `index_solid_events_incident_events_on_incident_action_time`

Expected usage patterns:

- Timeline lifecycle load:
  - `WHERE incident_id = ? ORDER BY occurred_at DESC LIMIT ?`
- API event filters:
  - `WHERE incident_id = ? AND action = ? ORDER BY occurred_at DESC LIMIT ?`

## Journey and causal-edge query planning

For materialized journey and causal graph APIs, ensure these indexes exist:

- `index_solid_events_journeys_on_journey_key`
- `index_solid_events_journeys_on_request_id`
- `index_solid_events_journeys_on_entity_type_and_entity_id`
- `index_solid_events_journeys_on_finished_at`
- `index_solid_events_causal_edges_on_from_trace_id`
- `index_solid_events_causal_edges_on_to_trace_id`
- `index_solid_events_causal_edges_uniqueness`

Expected usage patterns:

- Materialized journey polling:
  - `WHERE id < ? ORDER BY id DESC LIMIT ?`
- Journey slice by entity:
  - `WHERE entity_type = ? AND entity_id = ? ORDER BY id DESC LIMIT ?`
- Causal graph expansion around trace:
  - `WHERE from_trace_id = ? OR to_trace_id = ? ORDER BY id DESC LIMIT ?`

## Rollout guardrails for state-diff events

State-diff capture can increase event volume quickly. Guardrails:

- Keep `state_diff_allowlist` explicit during first rollout phase.
- Keep `state_diff_max_changed_fields` <= 20 for initial production rollout.
- Re-run benchmark checks after enabling each new allowlisted model class:

```bash
bundle exec rake "solid_events:benchmark_check[200,150,250]"
```
