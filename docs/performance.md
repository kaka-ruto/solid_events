# SolidEvents Performance Baseline

This baseline defines the initial query-performance targets for local/prod sanity checks.

## Benchmark command

```bash
bundle exec rake "solid_events:benchmark[200]"
```

## Initial targets

- `elapsed_ms <= 150` for sample size `200` on a typical developer machine
- `elapsed_ms <= 80` for sample size `200` on production-grade database hardware
- Repeatability target: three runs should stay within `+/-20%`

## Notes

- This benchmark is query-focused (read path) and does not measure ingestion throughput.
- Use this as a regression guard when adding indexes, filters, or timeline/metrics features.
