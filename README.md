# SolidEvents

**The "Context Graph" for Rails Applications.**

`SolidEvents` is a zero-configuration, database-backed observability engine for Rails 8+. It automatically unifies system tracing (Controller/SQL), business events, and record linkages into a single, queryable SQL interface.

By storing traces in your own database (PostgreSQL/SQLite), `SolidEvents` eliminates the need for expensive external observability tools (Datadog, New Relic) while enabling deeper, context-aware AI debugging.

## Scope

`SolidEvents` is strictly for observability and incident state:

- Detect incidents from canonical event/tracing data
- Store traces, events, summaries, and incident lifecycle state
- Expose that data through UI and APIs for humans and tools
- Manage incident state transitions (acknowledge, resolve, reopen, assign, mute)

It does **not** execute automation workflows (code fixes, PR creation, QA runs). That belongs in `solid_agents`.

---

## 🧐 The "Why"

### 1. Logs are Ephemeral, Decisions are Permanent

Traditional logs vanish. `SolidEvents` treats your application's execution history as **Business Data**. It captures the **Trace**—the exact sequence of decisions, logic branches, and data mutations—that led to a final state.

### 2. The Context Graph (Zero Config)

Most bugs are impossible to fix because you lack context.

- _Error:_ "Payment Failed."
- _Missing Context:_ "This request was triggered by User #5, and it attempted to create Order #99."
- _SolidEvents Solution:_ We **automatically** link the **Trace** (User Actions) to the **Record** (Order #99) to the **Error** (SolidErrors).

### 3. Owned Infrastructure

Stop renting your data.

- **Zero Monthly Cost:** No per-GB ingestion fees.
- **Privacy:** No PII leaves your server.
- **SQL Power:** Debug your app using standard SQL queries.

---

## 🛠 Features

- **⚡️ Auto-Instrumentation:** Automatically captures Controller Actions, Active Job executions, and SQL queries via `ActiveSupport::Notifications`.
- **🔗 Auto-Linking:** Automatically detects when an ActiveRecord model is created or updated during a request and links it to the Trace. (e.g., `Order.create` -> Linked to Trace).
- **🤖 Auto-Labeling:** Intelligently maps controller actions to business terms (e.g., `OrdersController#create` becomes `order.created`).
- **👤 Context Scraping:** Automatically detects `current_user`, `current_account`, or `tenant_id` from your controllers and tags the trace.
- **📊 Canonical Wide Events:** Maintains one summary row per trace with outcome, entity, HTTP, timing, and correlation fields for fast filtering.
- **🧾 Stable Schema Versioning:** Canonical events include `schema_version` for agent-safe parsing across upgrades.
- **🎯 Tail Sampling:** Keeps all failures and slow traces, then samples low-value successes by configurable rate.
- **🚢 Deploy-Aware Dimensions:** Captures service/environment/version/deployment/region on every canonical trace.
- **🔒 PII Redaction:** Redacts sensitive context/payload keys before persisting events and emitting logs.
- **🧯 Payload Size Guards:** Truncates oversized context/event payloads using configurable limits.
- **🧬 Path-Based Redaction:** Supports exact field-path redaction rules in addition to key matching.
- **🧱 Wide-Event Primary Mode:** Optionally skip sub-event row persistence while keeping canonical trace summaries complete.
- **🧹 Retention Tiers:** Keep success traces, error traces, and incidents for different durations.
- **🤖 Consumer APIs:** JSON endpoints for incidents and canonical traces at `/solid_events/api/...`.
- **📈 Compare Mode:** UI + API support for window-over-window error-rate and latency comparisons.
- **🧭 Journey Sequences:** UI panel + API to reconstruct request/entity trace sequences for story-first debugging.
- **🕒 Timeline View:** Ordered cross-trace timeline for request/entity investigations.
- **📌 Incident Timeline Markers:** Timeline view includes incident lifecycle milestones.
- **💾 Saved Views:** Persist and re-apply investigation filters directly from the traces dashboard.
- **🔗 Shared View Links:** Generate immutable shared-view URLs from saved filters for team handoff.
- **🔐 API Token Auth:** Optional token protection for all `/solid_events/api/*` endpoints.
- **📦 JSON Export:** Export filtered traces/incidents as JSON snapshots for handoff and auditing.
- **📡 Rails 8 Native:** Built on top of the new [Rails 8 Event Reporter API](https://api.rubyonrails.org/classes/ActiveSupport/EventReporter.html) and `SolidQueue` standards.

---

## 📦 Installation

Add this line to your application's Gemfile:

```ruby
gem "solid_events"
```

Then run the installer:

```bash
rails generate solid_events:install
rails db:migrate
```

### Recommended: SolidErrors

For a complete "Autonomous Reliability" stack, install `solid_errors`. `SolidEvents` will automatically detect it and link Traces to Errors.

```ruby
gem "solid_errors"
```

---

## 🚀 Zero-Configuration Behavior

Once installed, `SolidEvents` starts working immediately. You do **not** need to change your code.

### 1. Automatic Record Linking

When your app creates data, we link it.

```ruby
# Your existing code
def create
  @order = Order.create(params) # <-- SolidEvents automatically links this Order ID to the current Trace
end
```

### 2. Automatic Business Events

We automatically label controller actions with semantic names in the Dashboard:

| Controller Action               | Auto-Label      |
| :------------------------------ | :-------------- |
| `OrdersController#create` (201) | `order.created` |
| `UsersController#update` (200)  | `user.updated`  |
| `SessionsController#destroy`    | `session.ended` |

### 3. Automatic Context

If your controller has a `current_user` method (Devise/standard pattern), we automatically capture the `user_id` and add it to the Trace Context.

---

## ⚙️ Configuration

We provide sane defaults (ignoring internal Rails tables), but you can tune exactly what gets tracked.

```ruby
# config/initializers/solid_events.rb
SolidEvents.configure do |config|
  # 1. Database Isolation (Recommended)
  # Prevents logging writes from slowing down your main application.
  config.connects_to = { database: { writing: :solid_events } }

  # 2. Privacy & Noise Control
  # We automatically ignore SolidQueue, SolidCache, ActionMailbox, etc.
  # Add your own internal models here:
  config.ignore_models = [
    "Ahoy::Event",
    "AuditLog"
  ]

  # 3. Path Filtering
  # Don't log health checks or assets
  config.ignore_paths = ["/up", "/health", "/assets"]

  # 4. Namespace filtering (applies to model links, SQL, and job traces)
  # Defaults already include: solid_events, solid_errors, solid_queue,
  # solid_cache, solid_cable, active_storage, action_text
  config.ignore_namespaces << "paper_trail"
  config.allow_sql_tables << "noticed_notifications" # re-enable one table
  config.allow_job_prefixes << "job.active_storage" # re-enable if needed

  # 5. Retention Policy
  # Auto-delete logs older than 30 days
  config.retention_period = 30.days

  # 6. Tail Sampling (canonical wide-event style)
  # Keep all errors/slow traces, sample the rest.
  config.sample_rate = 0.2
  config.tail_sample_slow_ms = 1000
  config.always_sample_context_keys = ["release", "request_id"]
  config.always_sample_when = ->(trace:, context:, duration_ms:) { context["tenant_id"].present? }

  # 7. Emit one JSON line per sampled trace
  config.emit_canonical_log_line = true

  # 8. Deployment dimensions for cross-release debugging
  config.service_name = "anywaye"
  config.environment_name = Rails.env
  config.service_version = ENV["APP_VERSION"]
  config.deployment_id = ENV["DEPLOYMENT_ID"]
  config.region = ENV["APP_REGION"]

  # 9. Redaction policy
  config.sensitive_keys += ["customer_email", "phone_number"]
  config.redaction_paths = {
    "payment.card.number" => "[REDACTED_CARD]",
    "user.ssn" => true
  }
  config.redaction_placeholder = "[FILTERED]"
  config.max_context_payload_bytes = 16_384
  config.max_event_payload_bytes = 8_192
  config.payload_truncation_placeholder = "[TRUNCATED]"

  # 10. Feature slice dimensions captured into canonical payloads
  config.feature_slice_keys = %w[feature_flag experiment release_channel plan]

  # 11. Wide-event primary mode
  config.wide_event_primary = true
  config.persist_sub_events = false

  # 12. Retention tiers
  config.retention_period = 30.days
  config.error_retention_period = 90.days
  config.incident_retention_period = 180.days

  # 13. Optional Slack incident notifier
  # config.incident_notifier = SolidEvents::Notifiers::SlackWebhookNotifier.new(
  #   webhook_url: ENV.fetch("SOLID_EVENTS_SLACK_WEBHOOK_URL"),
  #   channel: "#incidents"
  # )
end
```

### High-Signal Logging Without Disabling Rails Logs

`SolidEvents` emits one canonical JSON line per sampled trace so teams can rely on stable, queryable events while keeping default Rails logs enabled.

### Add Business Context During Execution

You can enrich the current trace with product-specific dimensions from controllers, jobs, or services:

```ruby
SolidEvents.annotate!(
  plan: current_account.plan_name,
  cart_value_cents: @cart.total_cents,
  checkout_experiment: "checkout_v3"
)
```

### Agent-Friendly APIs

The mounted engine includes JSON endpoints for automation/agents:

- `GET /solid_events/api/incidents?status=active&limit=50`
- `GET /solid_events/api/incidents?status=active&limit=50&cursor=123`
- `GET /solid_events/api/incidents/:id/traces`
- `GET /solid_events/api/incidents/:id/context`
- `PATCH /solid_events/api/incidents/:id/acknowledge|resolve|reopen`
- `PATCH /solid_events/api/incidents/:id/assign` (`owner`, `team`, `assigned_by`, `assignment_note`)
- `PATCH /solid_events/api/incidents/:id/mute` (`minutes`)

Resolution metadata is supported via `PATCH /solid_events/api/incidents/:id/resolve`
with `resolved_by` and `resolution_note`.
- `GET /solid_events/api/traces/:id`
- `GET /solid_events/api/traces?error_fingerprint=...`
- `GET /solid_events/api/traces?entity_type=Order&entity_id=123`
- `GET /solid_events/api/traces?limit=50&cursor=456`
- `GET /solid_events/api/traces?feature_key=feature_flag&feature_value=checkout_v2`
- `GET /solid_events/api/metrics/error_rates?dimension=source&window=24h`
- `GET /solid_events/api/metrics/error_rates?dimension=source&feature_key=feature_flag&feature_value=checkout_v2`
- `GET /solid_events/api/metrics/latency?dimension=deployment_id&window=7d`
- `GET /solid_events/api/metrics/compare?metric=error_rate&dimension=source&window=24h`
- `GET /solid_events/api/metrics/cohorts?cohort_key=plan&metric=error_rate&window=24h`
- `GET /solid_events/api/journeys?request_id=req-123&window=24h`
- `GET /solid_events/api/journeys?entity_type=Order&entity_id=123&window=24h`
- `GET /solid_events/api/journeys?request_id=req-123&window=24h&errors_only=true`
- `GET /solid_events/api/export/traces?format=json&status=error&window=24h`
- `GET /solid_events/api/export/incidents?format=json&status=active`

Set `config.api_token` (or `SOLID_EVENTS_API_TOKEN`) to require `X-Solid-Events-Token` or `Authorization: Bearer <token>`.
List endpoints return `{ data: [...], next_cursor: <id|null> }` for cursor pagination.
Set `config.evaluate_incidents_on_request = false` in production if you only want job-driven evaluation.

`context` includes `solid_errors` enrichment when available.

API contract and versioning details: `docs/api.md`.

### Scheduling (Production)

To avoid relying on dashboard traffic, schedule these:

- `SolidEvents::EvaluateIncidentsJob.perform_later` every 5 minutes
- `SolidEvents::PruneJob.perform_later` daily

Rake alternatives (cron-friendly):

- `bin/rails solid_events:evaluate_incidents`
- `bin/rails solid_events:prune`

Example cron entries:

```cron
*/5 * * * * cd /app && bin/rails solid_events:evaluate_incidents RAILS_ENV=production
15 2 * * * cd /app && bin/rails solid_events:prune RAILS_ENV=production
```

Example `config/recurring.yml` (Solid Queue):

```yaml
production:
  evaluate_solid_events_incidents:
    class: "SolidEvents::EvaluateIncidentsJob"
    schedule: "every 5 minutes"
  prune_solid_events:
    class: "SolidEvents::PruneJob"
    schedule: "every day at 2:15am"
```

### Incident Response Runbook

Minimal flow your team/agents can automate:

1. `GET /solid_events/api/incidents?status=active`
2. For each incident: `GET /solid_events/api/incidents/:id/traces`
3. Execute fix workflow from canonical trace context.
4. Mark state with:
   - `PATCH /solid_events/api/incidents/:id/acknowledge`
   - `PATCH /solid_events/api/incidents/:id/resolve`

This gives a full closed-loop process without depending on raw Rails logs.

---

## 🕵️‍♀️ The Dashboard (Mission Control)

Mount the dashboard in your `config/routes.rb` to view your Context Graph.

```ruby
authenticate :user, ->(u) { u.admin? } do
  mount SolidEvents::Engine, at: "/solid_events"
end
```

**Features:**

- **Live Tail:** See requests coming in real-time.
- **Trace Waterfall:** Visualize the sequence: `Controller` -> `Model` -> `SQL` -> `Job`.
- **Entity Search:** Search for "Order 123" to see every trace that ever touched that order.
- **Dimension Filters:** Filter by entity type/id, context key/value, status, source, and minimum duration.
- **Fingerprint Filter:** Filter directly by canonical `error_fingerprint` from the traces index.
- **Request Correlation:** Filter and pivot by canonical `request_id` to stitch related traces instantly.
- **Correlation Pivots:** On each trace page, see related entity/error clusters and a simple duration regression signal.
- **Related Trace Exploration:** Jump from one trace to all traces sharing the same entity or error fingerprint.
- **Regression Surfacing:** Index highlights latency regressions and newly-seen error fingerprints.
- **Hot Paths & Percentiles:** Automatic p50/p95/p99 and error-rate visibility for top paths/jobs.
- **SLO Panels:** Throughput + error rate + p95/p99 at a glance for the active filter window.
- **Hot Path Drilldown:** Hourly p95 and recent failing traces for a selected route/job.
- **Incidents Feed:** Built-in detection for new fingerprints, error spikes, and p95 regressions.
- **Incident Lifecycle:** Acknowledge, resolve, and reopen incidents from the dashboard feed.
- **Incident Noise Control:** Suppression rules, dedupe windows, and notifier hooks for alert pipelines.
- **Deploy-Aware Error Detection:** Highlights fingerprints unique to current deploy/version.

---

## 🔮 The Future: SolidCopilot

`SolidEvents` is the data foundation for **SolidCopilot**, an AI agent that uses this data to:

1.  **Auto-Fix Bugs:** By reading the Trace History leading up to an error.
2.  **Generate Tests:** By converting real Production Traces into Minitest files.
3.  **Explain Architecture:** By visualizing the actual flow of data through your app.

_(Coming Soon)_

---

## 🤝 Contributing

This project is open source (MIT). We welcome contributions that align with the **"Solid"** philosophy: simple, SQL-backed, and Rails-native.

---

**License:** MIT
