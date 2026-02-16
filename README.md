# SolidEvents

**The "Context Graph" for Rails Applications.**

`SolidEvents` is a zero-configuration, database-backed observability engine for Rails 8+. It automatically unifies system tracing (Controller/SQL), business events, and record linkages into a single, queryable SQL interface.

By storing traces in your own database (PostgreSQL/SQLite), `SolidEvents` eliminates the need for expensive external observability tools (Datadog, New Relic) while enabling deeper, context-aware AI debugging.

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
- **🎯 Tail Sampling:** Keeps all failures and slow traces, then samples low-value successes by configurable rate.
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
end
```

### Replacing Rails Default Logs

`SolidEvents` emits one canonical JSON line per sampled trace, which is enough to replace default multi-line request logs.

```ruby
# config/environments/production.rb
config.log_tags = []
config.log_level = :info
```

```ruby
# config/initializers/disable_default_rails_logs.rb
ActiveSupport::LogSubscriber.log_subscribers.each do |subscriber|
  if subscriber.is_a?(ActionController::LogSubscriber) || subscriber.is_a?(ActiveRecord::LogSubscriber)
    subscriber.class.detach_from(subscriber.namespace)
  end
end
```

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
- **Correlation Pivots:** On each trace page, see related entity/error clusters and a simple duration regression signal.
- **Related Trace Exploration:** Jump from one trace to all traces sharing the same entity or error fingerprint.

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
