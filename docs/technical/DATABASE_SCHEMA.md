# Database Schema Architecture

This document describes the database schema architecture for Balados Sync, explaining the separation between permanent data and projections using two distinct Ecto Repositories.

## Overview

Balados Sync uses **2 Ecto Repositories** managing **4 PostgreSQL schemas**:

### Multi-Repository Architecture

```
┌──────────────────────────────────────────────────────────────────┐
│                  Balados Sync Data Layer                         │
├──────────────────────────────────────────────────────────────────┤
│                                                                  │
│  ┌─────────────────────┐    ┌──────────────────────────────┐   │
│  │   SystemRepo        │    │   ProjectionsRepo            │   │
│  │  (Permanent)        │    │  (Event-Sourced)             │   │
│  ├─────────────────────┤    ├──────────────────────────────┤   │
│  │  Schema: system     │    │  Schema: public              │   │
│  │  ├─ users           │    │  ├─ public_events           │   │
│  │  ├─ app_tokens      │    │  ├─ podcast_popularity      │   │
│  │  └─ play_tokens     │    │  └─ episode_popularity      │   │
│  │                     │    │                              │   │
│  │  Type: CRUD/Ecto    │    │  Type: Projectors/Commanded │   │
│  │  Reset: Destructive │    │  Reset: Safe (rebuild)      │   │
│  └─────────────────────┘    └──────────────────────────────┘   │
│                                                                  │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │  EventStore (Commanded)                                  │  │
│  │  Schema: events                                          │  │
│  │  ├─ streams, events, snapshots, projection_versions     │  │
│  │  Type: Immutable source of truth                         │  │
│  │  ⚠️  Never modify manually!                              │  │
│  └──────────────────────────────────────────────────────────┘  │
│                                                                  │
└──────────────────────────────────────────────────────────────────┘
```

### Configuration Options

**Option 1: Single PostgreSQL Database with Different Schemas (Default Development)**
```elixir
Database: balados_sync_dev
├─ schema: system    (managed by SystemRepo)
├─ schema: public    (managed by ProjectionsRepo)
└─ schema: events    (managed by EventStore/Commanded)
```

**Option 2: Separate PostgreSQL Databases (Recommended Production)**
```elixir
balados_sync_system       → SystemRepo (schema system)
balados_sync_projections  → ProjectionsRepo (schema public)
balados_sync_events       → EventStore (schema events)
```

Configuration in `config/prod.exs`:
```elixir
# SystemRepo on separate database
config :balados_sync_projections, BaladosSyncProjections.SystemRepo,
  database: "balados_sync_system",
  hostname: "db-system.example.com",
  pool_size: 10

# ProjectionsRepo on separate database
config :balados_sync_projections, BaladosSyncProjections.ProjectionsRepo,
  database: "balados_sync_projections",
  hostname: "db-projections.example.com",
  pool_size: 10

# EventStore on separate database (optional)
config :eventstore, EventStore.Config,
  database: "balados_sync_events",
  hostname: "db-events.example.com"
```

## Repository Breakdown

### SystemRepo - Managed by `mix system.migrate`

**Purpose:** Permanent infrastructure data for authentication and authorization.

**Schema:** `system`

**Characteristics:**
- ❌ NOT event-sourced (permanent architectural decision)
- ✅ Direct CRUD operations via Ecto
- 🔒 NEVER truncated by `mix db.reset --projections`
- 🔐 Uses standard security patterns (bcrypt, sessions)

**Tables:**

| Table | Description | Event-Sourced? | Reconstruable? |
|-------|-------------|----------------|----------------|
| `users` | User accounts (passwords, auth data) | ❌ NO | ❌ NO |
| `app_tokens` | Third-party app authorizations (JWT) | ❌ NO | ❌ NO |
| `play_tokens` | Play gateway bearer tokens | ❌ NO | ❌ NO |

**Why permanent and not event-sourced?**
- Authentication is well-understood with traditional CRUD patterns
- Compliance with standard security practices (bcrypt, OAuth)
- Clear separation: `system` = infrastructure, projections = domain logic
- Avoids unnecessary complexity for operational data
- Faster authentication (no event replay needed)

**Migration Management:**
```bash
# Generate migration
cd apps/balados_sync_projections
mix ecto.gen.migration add_column --prefix system

# Apply migration
mix system.migrate
# or
mix db.migrate  # applies both repos
```

---

### ProjectionsRepo - Managed by `mix projections.migrate`

**Purpose:** Denormalized read models built from domain events.

**Schema:** `public` (can also manage `users` schema if needed)

**Characteristics:**
- ✅ Event-sourced (built from EventStore)
- ✅ Can be safely truncated and rebuilt via `mix db.reset --projections`
- 🔄 Automatically reconstructed by projectors after reset
- 📊 Optimized for fast queries and aggregations

**Tables:**

| Table | Description | Rebuilt from Event(s) | Rebuilds in ~? |
|-------|-------------|----------------------|-----------------|
| `public_events` | Public activity feed | All events (filtered by privacy) | Seconds |
| `podcast_popularity` | Podcast popularity scores | `PopularityRecalculated` | Seconds |
| `episode_popularity` | Episode popularity scores | `PopularityRecalculated` | Seconds |
| `subscriptions` | User subscriptions (public aggregation) | `UserSubscribed`, `UserUnsubscribed` | Seconds |

**Migration Management:**
```bash
# Generate migration
cd apps/balados_sync_projections
mix ecto.gen.migration add_table

# Apply migration
mix projections.migrate
# or
mix db.migrate  # applies both repos
```

---

### EventStore - Managed by Commanded

**Purpose:** Immutable source of truth for all domain events.

**Schema:** `events`

**Characteristics:**
- ✅ Managed by Commanded/EventStore library
- ❌ NEVER modify manually (not even read-only queries)
- 🔒 Events are immutable (except deletion events)
- 🗑️  Deletion events suppress history (disappear after 45 days)
- 🎯 Single source of truth for all projections

**Tables:**
- `streams` - Event stream metadata and offsets
- `events` - All domain events (append-only log)
- `snapshots` - Aggregate snapshots for performance optimization
- `projection_versions` - Projector subscription positions

**Initialization:**
```bash
# Initialize once per database
mix event_store.init -a balados_sync_core

# Verify initialization
iex -S mix
EventStore.read_all_streams_forward()
```

**⚠️ WARNING:**
- Never run SQL directly against this schema
- Use Commanded APIs for event operations
- Never modify EventStore data manually
- If you delete events, projections will become stale

---

## Setup Commands

### `mix db.create` ✅ Initial Database Creation

**What it does:**
1. Creates the PostgreSQL database(s)
2. Creates the `system` schema via SystemRepo
3. Creates the `events` schema for EventStore
4. Prepares ProjectionsRepo configuration

**Use after:**
```bash
mix deps.get
```

**Example:**
```bash
mix db.create
```

**Configuration:**
- Uses `DATABASE_URL` for SystemRepo and EventStore
- Uses `EVENT_STORE_URL` if set, otherwise uses `DATABASE_URL`
- Can be configured to use separate databases

---

### `mix db.init` ✅ Initialize Everything at Once

**What it does (in order):**
1. Initializes the event store: `mix event_store.init -a balados_sync_core`
2. Runs migrations for the `system` schema: `mix system.migrate`

**This is the recommended way to initialize!** It combines both initialization steps.

**Use after:**
- `mix db.create`

**Example:**
```bash
mix db.create
mix db.init  # Replaces the need for separate event_store.init and migrations
```

**Note:** Does NOT migrate projections (they auto-rebuild from events)

---

### `mix db.migrate` - Migrate Both Repos

**What it does:**
1. Runs migrations for SystemRepo (`system` schema)
2. Runs migrations for ProjectionsRepo (`public` schema)

**When to use:**
- After creating new migrations
- To apply all pending migrations to both repos

**Example:**
```bash
# Create new migration for system
cd apps/balados_sync_projections
mix ecto.gen.migration add_column --prefix system

# Apply migrations to both repos
mix db.migrate
```

---

### `mix system.migrate` - Migrate SystemRepo Only

**What it does:**
- Runs migrations for the `system` schema only
- Orchestrated via Mix task

**When to use:**
- When you only need to migrate system tables
- Debugging/testing individual repo migrations

**Example:**
```bash
mix system.migrate
```

---

### `mix projections.migrate` - Migrate ProjectionsRepo Only

**What it does:**
- Runs migrations for the `public` schema only
- Orchestrated via Mix task

**When to use:**
- When you only need to migrate projections
- Debugging/testing individual repo migrations

**Example:**
```bash
mix projections.migrate
```

---

### `mix system_db.create` (Advanced)

**What it does:**
- Creates only the `system` schema
- Used internally by `mix db.create`

**When to use:**
- Rarely. Only if you need to recreate just the system schema.
- For testing separate repo initialization

---

### Migration File Generation

**For System Schema:**
```bash
cd apps/balados_sync_projections
mix ecto.gen.migration add_column_to_users --prefix system
# Creates: priv/system_repo/migrations/[timestamp]_add_column_to_users.exs
```

**For Projections Schema:**
```bash
cd apps/balados_sync_projections
mix ecto.gen.migration add_public_table
# Creates: priv/projections_repo/migrations/[timestamp]_add_public_table.exs
```

---

## Reset Commands Reference

### `mix db.reset --projections` ✅ SAFE

**What it does:**
- Drops and recreates only the `public` schema
- Resets projector subscription positions
- Triggers automatic rebuild from EventStore
- **Requires confirmation** by typing 'DELETE'

**What it preserves:**
- ✅ All `system` tables (users, tokens)
- ✅ All `events` (EventStore)

**When to use:**
- Development: Fast iteration on projectors
- Bug fixes: Corrupted projection data
- Schema changes: After migration of projection tables

**Example:**
```bash
$ mix db.reset --projections

✅ SAFE: You are about to reset projections only.

This will:
- Wipe public schema (trending, popularity data)
- Reset projector positions
- Trigger automatic rebuild from events

System data and events will be preserved.

Type 'DELETE' to confirm:
```

---

### `mix db.reset --system` ⚠️ DANGER

**What it does:**
- Drops and recreates only the `system` schema
- Deletes all users, API tokens, play tokens
- **Requires confirmation** by typing 'DELETE'

**What it preserves:**
- ✅ All projections (public schema)
- ✅ All events (EventStore)

**When to use:**
- Development: Fresh start with test users
- Testing: Clean slate for integration tests
- **NEVER in production!**

**Example:**
```bash
$ mix db.reset --system

⚠️  DANGER: You are about to delete all system data!
This includes: users, API tokens, play tokens

Events and projections will be preserved.

Type 'DELETE' to confirm:
```

---

### `mix db.reset --events` ☢️ EXTREME DANGER

**What it does:**
- Drops and recreates only the `events` schema
- Deletes ALL events from EventStore
- **CANNOT BE RECOVERED**
- **Requires confirmation** by typing 'DELETE ALL EVENTS'

**What it preserves:**
- ✅ All `system` tables (users, tokens)
- ✅ All `public` projections (but they become stale)

**When to use:**
- **ALMOST NEVER** - Only if you have backups and understand the consequences
- **NEVER in production!**

**Example:**
```bash
$ mix db.reset --events

☢️  EXTREME DANGER: You are about to delete all events!

⚠️  EVENTS ARE YOUR SOURCE OF TRUTH AND CANNOT BE RECOVERED

Type 'DELETE ALL EVENTS' to confirm:
```

---

### `mix db.reset --all` ☢️☢️ EXTREME DANGER

**What it does:**
- Drops entire database
- Recreates all schemas (`system`, `events`, `public`)
- Runs all migrations
- **Requires confirmation** by typing 'DELETE ALL DATA'

**What it deletes:**
- ❌ Everything in `system` (users, tokens)
- ❌ Everything in `public` (projections)
- ❌ Everything in `events` (CANNOT BE RECOVERED!)

**When to use:**
- Initial setup (if `db.create` failed)
- **EXTREME CAUTION in development**
- **NEVER in production!**

**After using this:**
You must re-initialize:
```bash
mix event_store.init -a balados_sync_core
mix db.init
```

**Example:**
```bash
$ mix db.reset --all

☢️  EXTREME DANGER: You are about to delete EVERYTHING!

Type 'DELETE ALL DATA' to confirm:
```

---

### ⚠️ DO NOT USE: `mix ecto.reset`, `ecto.drop`, `ecto.migrate`, `ecto.create`

These commands are **overridden** to prevent accidental misuse. If you try:

```bash
$ mix ecto.reset
❌ ERROR: Do not use 'mix ecto.reset' directly!

Use the safe wrapper instead: 'mix db.reset'
```

**Always use:**
- `mix db.*` for database operations
- `mix system_db.*` for system schema only
- `mix db.reset --[option]` for resets with validation

---

## Decision Tree: Which Command to Use?

### Initial Setup

```bash
# 1. Install dependencies
mix deps.get

# 2. Create database and schemas
mix db.create

# 3. Initialize event store + migrate system (ONE COMMAND!)
mix db.init

# Done! Now start your server
mix phx.server
```

### During Development

```
Need to do something with the database?
│
├─ Apply pending migrations (system schema)?
│  └─ ✅ Use: mix db.migrate
│
├─ Reset data?
│  │
│  ├─ Only projections corrupted/outdated?
│  │  └─ ✅ Use: mix db.reset --projections
│  │
│  ├─ Need fresh users/tokens for testing?
│  │  └─ ⚠️  Use: mix db.reset --system
│  │
│  ├─ Troubleshoot event store (EXTREME!)?
│  │  └─ ☢️  Use: mix db.reset --events
│  │
│  └─ Complete fresh start (EXTREME!)?
│     └─ ☢️☢️ Use: mix db.reset --all
│
└─ Just testing a feature?
   └─ ✅ Don't reset! Just create test data instead.
```

### Safety Guarantees

✅ All `db.*` commands:
- Ask for confirmation before deleting anything
- Tell you exactly what will be deleted
- Preserve data when possible (projections are rebuilt, not lost)

❌ Never use (blocked):
- `mix ecto.reset` → Use `mix db.reset --[option]` instead
- `mix ecto.drop` → Use `mix db.reset` instead
- `mix ecto.create` → Use `mix db.create` instead
- `mix ecto.migrate` → Use `mix db.migrate` instead

---

## Workflow Examples

### Development: Testing Projector Changes

```bash
# 1. Make changes to projector code
vim apps/balados_sync_projections/lib/projectors/subscriptions_projector.ex

# 2. Reset projections only to rebuild (SAFE)
mix db.reset --projections

# Confirm when prompted
Type 'DELETE' to confirm: DELETE

# 3. Verify rebuild worked
iex -S mix
iex> Repo.all(Subscription)
```

### Development: Fresh Start with New Users

```bash
# 1. Reset system schema (keeps events and projections)
mix db.reset --system

# Confirm when prompted
Type 'DELETE' to confirm: DELETE

# 2. Create new admin user
open http://localhost:4000/setup
```

### Development: Complete Fresh Start

```bash
# ☢️ Nuclear option - deletes everything
mix db.reset --all

# Confirm when prompted
Type 'DELETE ALL DATA' to confirm: DELETE ALL DATA

# Re-initialize
mix db.init

# Server will auto-restart
# Visit http://localhost:4000/setup for initial admin
```

### Development: Create a New Migration for System Schema

```bash
# 1. Generate migration file
cd apps/balados_sync_projections
mix ecto.gen.migration add_column_to_users --prefix system
cd ../..

# Edit the migration file

# 2. Apply the migration
mix db.migrate
```

---

## Architecture Decisions

### Decision 1: Two Distinct Ecto Repositories

**Decision:** Use separate Ecto Repositories for different concerns:
- **SystemRepo** manages infrastructure data (`system` schema)
- **ProjectionsRepo** manages read models (`public` schema)

**Rationale:**

1. **Clear Separation of Concerns:**
   - SystemRepo = Infrastructure (authentication, authorization)
   - ProjectionsRepo = Domain projections (derived read models)

2. **Operational Independence:**
   - Can be deployed on separate databases
   - Each repo has its own migration tracking
   - Allows independent scaling/backup strategies

3. **Flexibility:**
   - Development: Single PostgreSQL with 3 schemas
   - Production: Separate databases for each repo + events
   - Both configurations supported via Elixir config

4. **Future-Proof:**
   - Easy to move projections to separate database for read-heavy workloads
   - Can implement caching layers, replicas for projections only
   - System schema remains stable and simple

**Benefits:**
- Clear migration isolation (no schema_migrations conflicts)
- Independent reset strategies (can reset projections without touching system)
- Better for scaling (projections can be read-only replicas)
- Easier to understand each repo's purpose

**Trade-offs:**
- Configuration complexity for separate databases
- Must carefully manage foreign keys between repos (none should exist)
- Each repo needs its own connection pool management

**Implementation:**
```
apps/balados_sync_projections/
├── lib/
│   ├── system_repo.ex          # SystemRepo module
│   └── projections_repo.ex     # ProjectionsRepo module
└── priv/
    ├── system_repo/migrations/     # System schema migrations
    └── projections_repo/migrations/ # Projections schema migrations
```

---

### Decision 2: System Schema ≠ CQRS/Event Sourcing

**Decision:** The `system` schema will **NEVER** be migrated to CQRS/Event Sourcing.

**Rationale:**

1. **Simplicity:** Authentication is well-understood with traditional CRUD
2. **Standards:** bcrypt, sessions, OAuth follow established patterns
3. **Separation of Concerns:**
   - `system` = Infrastructure (how the app operates)
   - projections = Domain (what users do)
4. **Avoid Complexity:** Event-sourcing user accounts adds little value
5. **Security:** Direct password hashing is simpler to audit

**Trade-offs accepted:**
- System data is not replayable from events
- No temporal queries on user account history
- Cannot rebuild system state from EventStore

**Benefits:**
- Faster authentication (no event replay)
- Simpler to reason about
- Standard security practices
- Clear architectural boundaries

---

### Decision 3: Single or Multiple Databases

**Decision:** Support both patterns:
- **Development:** Single PostgreSQL database with 3 schemas
- **Production:** Separate databases for each repo + EventStore

**Rationale:**

1. **Development Experience:** Simple setup, no extra infrastructure
2. **Production Scalability:** Separate databases allow independent scaling
3. **Operational Flexibility:** Teams can choose their strategy

**Configuration:**

```elixir
# Development: Single database
config :balados_sync_projections, BaladosSyncProjections.SystemRepo,
  database: "balados_sync_dev"

config :balados_sync_projections, BaladosSyncProjections.ProjectionsRepo,
  database: "balados_sync_dev"  # Same database

# Production: Separate databases
config :balados_sync_projections, BaladosSyncProjections.SystemRepo,
  database: "balados_sync_system",
  hostname: "db-system.example.com"

config :balados_sync_projections, BaladosSyncProjections.ProjectionsRepo,
  database: "balados_sync_projections",
  hostname: "db-projections.example.com"
```

**Benefits:**
- No architectural lock-in
- Allows gradual scaling as system grows
- Each org can choose their database strategy

---

## Table Classification Reference

Complete list of all tables with classification:

### System Schema (Permanent)

| Table | Type | Rebuilt from Events? | Safe to Truncate? |
|-------|------|---------------------|-------------------|
| `system.users` | Permanent | ❌ No | ❌ No |
| `system.app_tokens` | Permanent | ❌ No | ❌ No |
| `system.play_tokens` | Permanent | ❌ No | ❌ No |

### Users Schema (Projections)

| Table | Type | Rebuilt from Events? | Safe to Truncate? |
|-------|------|---------------------|-------------------|
| `users.subscriptions` | Projection | ✅ Yes | ✅ Yes |
| `users.play_statuses` | Projection | ✅ Yes | ✅ Yes |
| `users.playlists` | Projection | ✅ Yes | ✅ Yes |
| `users.playlist_items` | Projection | ✅ Yes | ✅ Yes |
| `users.user_privacy` | Projection | ✅ Yes | ✅ Yes |

### Public Schema (Projections)

| Table | Type | Rebuilt from Events? | Safe to Truncate? |
|-------|------|---------------------|-------------------|
| `public.podcast_popularity` | Projection | ✅ Yes | ✅ Yes |
| `public.episode_popularity` | Projection | ✅ Yes | ✅ Yes |
| `public.public_events` | Projection | ✅ Yes | ✅ Yes |

### Events Schema (EventStore)

| Table | Type | Managed by |
|-------|------|------------|
| `events.streams` | EventStore | Commanded |
| `events.events` | EventStore | Commanded |
| `events.snapshots` | EventStore | Commanded |
| `events.projection_versions` | EventStore | Commanded |

**⚠️ Never modify EventStore tables manually!**

---

## Migration Guide

If you need to add a new table, follow this decision tree:

### Should this be in `system` or a projection?

**Ask yourself:**

1. **Is this authentication/authorization data?**
   - Yes → `system`
   - No → Continue

2. **Can this data be rebuilt from events?**
   - No → `system`
   - Yes → Projection (`users` or `public`)

3. **Is this user-scoped or public?**
   - User-scoped → `users`
   - Public → `public`

### Example: Adding User Preferences

```elixir
# 1. Is it auth data? No.
# 2. Can be rebuilt from events? Yes, emit PreferencesChanged event.
# 3. User-scoped or public? User-scoped.
# → Create in `users` schema as a projection

# migration
create table(:user_preferences, prefix: "users") do
  # ...
end

# schema
@schema_prefix "users"
schema "user_preferences" do
  # ...
end
```

---

## FAQ

**Q: Can I manually insert rows into projection tables for testing?**
A: Yes, but `mix reset_projections` will wipe them. Better to emit events instead.

**Q: What happens if I run `mix reset_projections` while the app is running?**
A: The projectors will detect the reset and automatically rebuild. Safe to do.

**Q: Can I reset just one projection?**
A: Not with the built-in tasks. You can manually truncate the table and delete from `projection_versions` for that projector.

**Q: How long does `mix reset_projections` take?**
A: Depends on number of events. Typically seconds for dev, could be minutes for production-scale data.

**Q: Why can't I just use `mix ecto.reset` for everything?**
A: It deletes EventStore events which are your source of truth. Once deleted, data is GONE forever.

**Q: What if I accidentally run `mix ecto.reset!`?**
A: Hope you have backups. There's no undo. This is why confirmation is required by default.

---

## Related Documentation

- [ARCHITECTURE.md](ARCHITECTURE.md) - Overall system architecture
- [CQRS_PATTERNS.md](CQRS_PATTERNS.md) - CQRS/ES patterns and best practices
- [DEVELOPMENT.md](DEVELOPMENT.md) - Development workflow and commands

---

**Last Updated:** 2025-11-26
**Status:** 🟢 Canonical Reference - Multi-Repo Architecture Documented
