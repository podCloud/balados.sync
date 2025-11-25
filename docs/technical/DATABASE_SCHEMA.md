# Database Schema Architecture

This document describes the database schema architecture for Balados Sync, explaining the separation between permanent data and projections.

## Overview

Balados Sync uses **4 PostgreSQL schemas** to organize data:

```
┌─────────────────────────────────────────────────────────────┐
│                      PostgreSQL Database                     │
├─────────────────────────────────────────────────────────────┤
│  system     │  Permanent data (non event-sourced)          │
│  users      │  Projections from events (user-scoped)       │
│  public     │  Projections from events (public data)       │
│  events     │  EventStore (Commanded)                      │
└─────────────────────────────────────────────────────────────┘
```

## Schema Breakdown

### 1. `system` - Permanent Infrastructure Data

**Purpose:** Infrastructure data required for application operation.

**Characteristics:**
- ❌ NOT event-sourced
- ✅ Direct CRUD operations via Ecto
- ⚠️  NEVER truncated by `mix reset_projections`
- 🔒 This is a **permanent architectural decision** (will not evolve to CQRS/ES)

**Tables:**

| Table | Description | Safe to Truncate? |
|-------|-------------|-------------------|
| `users` | User accounts (passwords, auth data) | ❌ NO |
| `app_tokens` | Third-party app authorizations (JWT) | ❌ NO |
| `play_tokens` | Play gateway bearer tokens | ❌ NO |

**Why not event-sourced?**
- Simplicity for authentication/authorization
- Compliance with standard auth patterns (bcrypt, sessions)
- Clear separation: system = infrastructure, others = domain
- Avoids unnecessary complexity for operational data

---

### 2. `users` - User-Scoped Projections

**Purpose:** Denormalized read models for user-specific data.

**Characteristics:**
- ✅ Event-sourced (built from EventStore)
- ✅ Can be safely truncated and rebuilt
- 🔄 Automatically reconstructed via projectors

**Tables:**

| Table | Description | Rebuilt from Event |
|-------|-------------|-------------------|
| `subscriptions` | User podcast subscriptions | `UserSubscribed`, `UserUnsubscribed` |
| `play_statuses` | Episode listening progress | `PlayRecorded`, `PositionUpdated` |
| `playlists` | User custom playlists | (Future: playlist events) |
| `playlist_items` | Items in playlists | (Future: playlist events) |
| `user_privacy` | User privacy settings | `PrivacyChanged` |

---

### 3. `public` - Public Projections

**Purpose:** Public-facing data and aggregations.

**Characteristics:**
- ✅ Event-sourced (built from EventStore)
- ✅ Can be safely truncated and rebuilt
- 🌐 Publicly accessible (no authentication required)

**Tables:**

| Table | Description | Rebuilt from Event |
|-------|-------------|-------------------|
| `podcast_popularity` | Podcast popularity scores | `PopularityRecalculated`, play events |
| `episode_popularity` | Episode popularity scores | `PopularityRecalculated`, play events |
| `public_events` | Public activity feed | Various events (filtered by privacy) |

---

### 4. `events` - EventStore

**Purpose:** Immutable source of truth for all domain events.

**Characteristics:**
- ✅ Managed by Commanded/EventStore
- ❌ NEVER modify manually
- 🔒 Events are immutable (except deletion events)
- 🗑️  Deletion events suppress history (disappear after 45 days)

**Tables:**
- `streams` - Event stream metadata
- `events` - All domain events
- `snapshots` - Aggregate snapshots for performance

**⚠️ WARNING:** Never run SQL directly against this schema. Use Commanded APIs.

---

## Reset Commands Reference

### `mix reset_projections` ✅ SAFE

**What it does:**
- Truncates `users` schema tables (projections only)
- Truncates `public` schema tables (projections only)
- Resets projector subscription positions
- Triggers automatic rebuild from EventStore

**What it preserves:**
- ✅ All `system` tables (users, tokens)
- ✅ All `events` (EventStore)

**When to use:**
- Development: Fast iteration on projectors
- Bug fixes: Corrupted projection data
- Schema changes: After migration of projection tables

**Example:**
```bash
mix reset_projections
```

---

### `mix reset_system` ⚠️ DANGER

**What it does:**
- Truncates `system.users` (all accounts deleted!)
- Truncates `system.app_tokens` (all auth deleted!)
- Truncates `system.play_tokens` (all tokens deleted!)

**What it preserves:**
- ✅ All projections (users, public schemas)
- ✅ All events (EventStore)

**When to use:**
- Development: Fresh start with test users
- Testing: Clean slate for integration tests
- **NEVER in production!**

**Example:**
```bash
$ mix reset_system

⚠️  DANGER: You are about to delete all system data!
Type 'DELETE SYSTEM DATA' to confirm:
```

---

### `mix ecto.reset` ☢️ EXTREME DANGER

**What it does:**
- Drops entire database
- Recreates database
- Runs all migrations
- Runs seeds

**What it deletes:**
- ❌ Everything in `system`
- ❌ Everything in `users`
- ❌ Everything in `public`
- ❌ Everything in `events` (CANNOT BE RECOVERED!)

**When to use:**
- Initial setup
- Major schema migrations
- **EXTREME CAUTION in development**
- **NEVER in production!**

**Example:**
```bash
$ mix ecto.reset

⚠️  EXTREME DANGER: You are about to delete ALL DATA!
Type 'DELETE ALL DATA' to confirm:
```

**Force without confirmation:**
```bash
mix ecto.reset!  # Use with extreme caution!
```

---

## Decision Tree: Which Command to Use?

```
Need to reset data?
│
├─ Only projections corrupted/outdated?
│  └─ ✅ Use: mix reset_projections
│
├─ Need to clear test users/tokens?
│  └─ ⚠️  Use: mix reset_system
│
├─ Major schema migration or starting fresh?
│  └─ ☢️  Use: mix ecto.reset (or ecto.reset!)
│
└─ Just testing a feature?
   └─ ✅ Don't reset! Just create test data.
```

---

## Workflow Examples

### Development: Testing Projector Changes

```bash
# 1. Make changes to projector code
vim apps/balados_sync_projections/lib/projectors/subscriptions_projector.ex

# 2. Reset projections to rebuild
mix reset_projections

# 3. Verify rebuild worked
iex -S mix
iex> Repo.all(Subscription)
```

### Development: Fresh Start with New User

```bash
# Reset system data (keeps events if any)
mix reset_system

# Create new admin user via web interface
open http://localhost:4000/setup
```

### Development: Complete Fresh Start

```bash
# Nuclear option - deletes everything
mix ecto.reset

# Server will auto-restart
# Visit http://localhost:4000/setup for initial admin
```

---

## Architecture Decision: Why System ≠ CQRS/ES?

**Decision:** The `system` schema will **NEVER** be migrated to CQRS/Event Sourcing.

**Rationale:**

1. **Simplicity:** Authentication is well-understood with traditional CRUD
2. **Standards:** bcrypt, sessions, OAuth follow established patterns
3. **Separation of Concerns:**
   - `system` = Infrastructure (how the app operates)
   - `users`/`public` = Domain (what users do)
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

**Last Updated:** 2025-11-25
**Status:** 🟢 Canonical Reference
