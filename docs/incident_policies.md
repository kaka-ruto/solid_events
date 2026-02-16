# Incident Policy Defaults by Environment

These defaults are designed to keep development quiet, staging useful for release validation, and production sensitive to customer impact.

## Recommended baseline

```ruby
SolidEvents.configure do |config|
  case Rails.env
  when "development"
    config.incident_error_spike_threshold_pct = 40.0
    config.incident_p95_regression_factor = 2.0
    config.incident_slo_target_error_rate_pct = 5.0
    config.incident_slo_burn_rate_threshold = 4.0
    config.incident_multi_signal_error_rate_pct = 25.0
    config.incident_multi_signal_p95_factor = 2.0
    config.incident_multi_signal_sql_duration_ms = 500.0
    config.incident_min_samples = 10
  when "staging"
    config.incident_error_spike_threshold_pct = 25.0
    config.incident_p95_regression_factor = 1.7
    config.incident_slo_target_error_rate_pct = 2.0
    config.incident_slo_burn_rate_threshold = 3.0
    config.incident_multi_signal_error_rate_pct = 15.0
    config.incident_multi_signal_p95_factor = 1.6
    config.incident_multi_signal_sql_duration_ms = 300.0
    config.incident_min_samples = 15
  else # production
    config.incident_error_spike_threshold_pct = 20.0
    config.incident_p95_regression_factor = 1.5
    config.incident_slo_target_error_rate_pct = 1.0
    config.incident_slo_burn_rate_threshold = 2.0
    config.incident_multi_signal_error_rate_pct = 10.0
    config.incident_multi_signal_p95_factor = 1.4
    config.incident_multi_signal_sql_duration_ms = 200.0
    config.incident_min_samples = 20
  end
end
```

## Why these numbers

- Development: avoid noisy incidents while iterating locally.
- Staging: catch regressions before deploy, but tolerate synthetic traffic variance.
- Production: detect customer-facing degradation quickly, including burn rate and multi-signal failures.

## Operational notes

- Keep `incident_dedupe_window` at `1.hour` unless your app has bursty error patterns that require longer suppression.
- Use `incident_suppression_rules` for known non-actionable events (health checks, synthetic probes).
- If incidents are too noisy, raise `incident_min_samples` before increasing all thresholds.
