# Architectural Audit Report - Balados Sync

**Audit Date**: 2025-12-21
**Auditor**: Claude (Opus 4.5)
**Project Version**: 0.1.0

---

## Executive Summary

Balados Sync is a well-architected Elixir/Phoenix application implementing CQRS/Event Sourcing for podcast synchronization. The project demonstrates solid architectural decisions with proper separation of concerns across its umbrella structure. However, there are opportunities for improvement in testing coverage, dependency management, and addressing technical debt.

**Overall Assessment**: **B+ (Good with Notable Strengths)**

| Category | Score | Status |
|----------|-------|--------|
| Architecture & Patterns | A- | Excellent |
| Code Quality | B+ | Good |
| Security | B+ | Good |
| Testing | B- | Needs Improvement |
| Database Design | A- | Excellent |
| Documentation | A | Excellent |

---

## 1. Architecture & Patterns

### 1.1 CQRS/Event Sourcing Implementation

**Assessment: Excellent**

The CQRS/ES implementation is **correct and consistent**. The project properly separates:

#### Write Side (Commands)
- Commands are simple structs with clear type specifications
- Example: `/apps/balados_sync_core/lib/balados_sync_core/commands/subscribe.ex`
```elixir
defstruct [
  :user_id,
  :rss_source_feed,
  :rss_source_id,
  :subscribed_at,
  :event_infos
]
```

#### Command Handling
- User aggregate (`/apps/balados_sync_core/lib/balados_sync_core/aggregates/user.ex`) handles 20+ commands
- `execute/2` functions properly validate and emit events
- `apply/2` functions correctly update aggregate state

#### Read Side (Projections)
- 6 projectors handle event-to-read-model transformation
- Proper use of `Commanded.Projections.Ecto` for projection management
- Eventual consistency model is properly documented

**Strengths:**
- Clear separation between commands and events
- Well-documented aggregate with comprehensive moduledoc
- Proper use of Commanded router for command dispatching
- Events derive `Jason.Encoder` for serialization

**Concerns:**
- User aggregate is large (1030 lines) - consider splitting by bounded context
- Some `apply/2` clauses have no-op fallback: `def apply(%__MODULE__{} = user, _event), do: user`

### 1.2 Umbrella App Separation

**Assessment: Good**

The 4 umbrella apps are **properly separated** with correct dependency flow:

```
balados_sync_web
    |
    +---> balados_sync_core <---+
    |                           |
    +---> balados_sync_projections
                                ^
                                |
balados_sync_jobs --------------+
```

#### App Responsibilities

| App | Responsibility | Dependencies |
|-----|----------------|--------------|
| `balados_sync_core` | Domain, CQRS, Event Store | None (foundation) |
| `balados_sync_projections` | Read models, Projectors | core |
| `balados_sync_web` | REST API, Controllers, UI | core, projections |
| `balados_sync_jobs` | Background workers | core, projections |

**Strengths:**
- No circular dependencies detected
- Each app has its own Application module
- Proper OTP supervision trees

**Concerns:**
- `RssCache` and `RssParser` are in `balados_sync_core` but logically belong to infrastructure
- Some modules like `EnrichedPodcasts` context are in `web` but could be in a shared context

### 1.3 Dependency Flow Analysis

**Assessment: Good**

Dependencies flow correctly from domain (core) outward:

```elixir
# core/mix.exs - No in_umbrella deps
deps: [
  {:commanded, "~> 1.4"},
  {:eventstore, "~> 1.4"},
  ...
]

# projections/mix.exs
deps: [
  {:balados_sync_core, in_umbrella: true},
  ...
]

# web/mix.exs
deps: [
  {:balados_sync_core, in_umbrella: true},
  {:balados_sync_projections, in_umbrella: true},
  ...
]
```

---

## 2. Code Quality

### 2.1 Code Smells and Anti-Patterns

**Assessment: Good with some concerns**

#### Identified Issues

| Issue | Severity | Location | Description |
|-------|----------|----------|-------------|
| Large aggregate | Medium | `user.ex` (1030 lines) | Consider splitting by domain |
| Code duplication | Low | `rss_aggregate_controller.ex` | `aggregate_subscription_feeds` and `aggregate_collection_feeds` are nearly identical |
| Missing error context | Medium | Multiple controllers | `{:error, reason}` without structured errors |
| Magic strings | Low | `snapshot_worker.ex` | Raw SQL with hardcoded table names |

#### TODOs and FIXMEs Found

```
apps/balados_sync_web/controllers/sync_controller.ex:64 - TODO: implement sync structure
apps/balados_sync_core/aggregates/user.ex:25 - TODO: playlists documentation
apps/balados_sync_core/aggregates/user.ex:349 - TODO: Sync playlists not implemented
apps/balados_sync_projections/schemas/user.ex:88 - TODO: Switch to Argon2
apps/balados_sync_jobs/snapshot_worker.ex:38 - TODO: EventStore API simplification
```

### 2.2 Error Handling

**Assessment: Inconsistent**

- JWT auth returns structured errors: `%{error: "Unauthorized"}`
- Some controllers expose raw error reasons: `json(%{error: inspect(reason)})`
- Missing centralized error handling module

**Recommendation**: Create a dedicated `BaladosSyncWeb.ErrorHelpers` module.

### 2.3 N+1 Query Analysis

**Assessment: Good - mostly addressed**

The codebase shows awareness of N+1 issues:

```elixir
# Good: Batched metadata fetching in PublicController
defp build_feed_metadata_map(encoded_feeds) do
  Enum.reduce(encoded_feeds, %{}, fn encoded_feed, acc ->
    ...
  end)
end
```

**Potential N+1 issues:**
- `PrivacyManagerController.index/2` fetches metadata for each subscription
- Timeline HTML fetches feed metadata in a loop

### 2.4 Logging

**Assessment: Good**

- Proper use of `require Logger` throughout
- Debug, info, and error levels used appropriately
- JWT auth logs failures at debug level (correct for security)

```elixir
Logger.debug("JWT auth failed: #{inspect(error)}")
```

---

## 3. Security

### 3.1 Authentication Implementation

**Assessment: Good**

#### JWT (RS256) for API
- Proper asymmetric key cryptography
- Public key stored per app for verification
- Scopes validated before action execution

```elixir
# JWTAuth plug pattern
plug JWTAuth, [scopes: ["user.subscriptions.read"]] when action in [:index, :metadata]
```

#### Session-based for Web UI
- Using Phoenix's built-in session handling
- `UserAuth` plug for session management
- CSRF protection enabled via `:protect_from_forgery`

### 3.2 Scope System

**Assessment: Excellent**

Well-designed hierarchical scope system:

```
*                         (full access)
+-- *.read / *.write
+-- user
    +-- user.subscriptions.{read,write}
    +-- user.plays.{read,write}
    +-- user.playlists.{read,write}
    +-- user.privacy.{read,write}
    +-- user.sync
```

The `Scopes` module properly handles:
- Exact matches
- Wildcard patterns (`*`, `*.read`, `user.*`)
- Hierarchical matching (parent grants child)

### 3.3 Input Validation

**Assessment: Needs Improvement**

| Endpoint | Validation Status | Notes |
|----------|-------------------|-------|
| `/api/v1/subscriptions` | Partial | No feed URL validation |
| `/api/v1/play` | Partial | Position not validated |
| `/privacy/set/:feed` | Good | Privacy level validated |
| `/podcast-ownership` | Good | Rate limiting implemented |

**Concerns:**
- Base64-encoded feeds not validated for valid URLs after decoding
- No request body size limits visible
- No rate limiting on most API endpoints (only ownership)

### 3.4 Potential Vulnerabilities

| Risk | Severity | Description | Mitigation |
|------|----------|-------------|------------|
| SSRF | Medium | RSS fetching uses user-provided URLs | Add URL validation |
| DoS | Medium | No rate limiting on API | Add Hammer to more endpoints |
| Info Leak | Low | `inspect(reason)` exposes internals | Sanitize error messages |

---

## 4. Testing

### 4.1 Test Coverage Assessment

**Assessment: Needs Improvement**

| Metric | Value |
|--------|-------|
| Test files | 34 |
| Test lines | ~8,578 |
| Controllers with tests | 8 of 25 (32%) |
| Aggregates with tests | 3 |
| Projectors with tests | 3 of 6 (50%) |

#### Controllers Lacking Tests
- `SyncController`
- `PrivacyController`
- `PlayController`
- `EpisodeController`
- `AdminController`
- `SetupController`
- `RssProxyController`
- `PrivacyManagerController`
- `WebSubscriptionsController`
- `LiveWebSocketController`
- `EnrichedPodcastsController` (partial)
- And more...

### 4.2 Test Patterns

**Strengths:**
- `ConnCase` and `DataCase` properly set up
- Sandbox mode for database isolation
- Integration tests for WebSocket
- Unit tests for aggregates

**Missing Test Types:**
- [ ] Property-based tests (StreamData)
- [ ] Load/performance tests
- [ ] End-to-end API tests
- [ ] Contract tests for CQRS

### 4.3 Critical Paths Not Fully Tested

1. **Sync endpoint** - No tests for conflict resolution
2. **Event replay** - No tests for projection rebuild
3. **Checkpoint/Snapshot** - Worker logic untested
4. **Rate limiting** - Hammer integration not tested

---

## 5. Database Design

### 5.1 Schema Design

**Assessment: Excellent**

Three-schema approach is well-designed:

| Schema | Purpose | Tables |
|--------|---------|--------|
| `system` | Permanent data | users, app_tokens, play_tokens, enriched_podcasts |
| `public` | Event-sourced projections | subscriptions, playlists, collections, etc. |
| `events` | EventStore | Managed by Commanded |

### 5.2 Migration Patterns

**Assessment: Good**

- 29 migrations total (system + projections)
- Proper use of `prefix:` for schema separation
- Indexes defined appropriately
- Soft-delete pattern with `deleted_at` columns

**Example good migration:**
```elixir
create table(:subscriptions, primary_key: false, prefix: "users") do
  add :id, :binary_id, primary_key: true
  ...
end

create unique_index(:subscriptions, [:user_id, :rss_source_feed], prefix: "users")
create index(:subscriptions, [:user_id], prefix: "users")
create index(:subscriptions, [:rss_source_feed], prefix: "users")
```

### 5.3 Index Usage

**Assessment: Good**

Key indexes identified:
- Unique constraint on `(user_id, rss_source_feed)` for subscriptions
- Partial index for active subscriptions
- Indexes on foreign keys
- Expiration index on play_tokens for cleanup

**Potential missing indexes:**
- `public_events.event_type` for timeline filtering
- `playlists.is_public` for public profile queries

---

## 6. What's Good

### Architectural Strengths

1. **Proper CQRS/ES Implementation** - Commands, events, aggregates, and projectors follow best practices

2. **Clean Separation of Concerns** - Umbrella structure keeps domain, infrastructure, and presentation separate

3. **Flexible Auth System** - Dual auth (JWT for API, session for web) with hierarchical scopes

4. **Privacy-First Design** - Three-level privacy (public/anonymous/private) with granular control

5. **Event Sourcing Benefits Realized**
   - Complete audit trail
   - Projections can be rebuilt
   - Temporal queries possible

6. **Excellent Documentation** - CLAUDE.md, FEATURES.md, ARCHITECTURE.md are comprehensive

7. **Safe Database Operations** - Custom mix tasks prevent accidental ecto operations

8. **Async Processing** - Background jobs for cleanup, snapshots, popularity calculation

### Code Quality Highlights

- TypeScript for frontend (strict mode)
- Proper use of Ecto.Multi for transactional projections
- Well-structured Phoenix router with clear pipelines
- Modular RSS parsing and caching

---

## 7. What Needs Improvement

### Priority 1: Critical

| Issue | Impact | Effort | Recommendation |
|-------|--------|--------|----------------|
| Test coverage | High | High | Add tests for critical paths (sync, play, privacy) |
| Input validation | High | Medium | Validate all user inputs, especially URLs |
| Rate limiting | High | Low | Add Hammer to API endpoints |

### Priority 2: Important

| Issue | Impact | Effort | Recommendation |
|-------|--------|--------|----------------|
| Error handling | Medium | Medium | Centralize with structured errors |
| Large aggregate | Medium | High | Split User aggregate by bounded context |
| TODOs | Medium | Medium | Address sync_controller and playlist sync |
| N+1 queries | Medium | Low | Batch metadata fetching in privacy manager |

### Priority 3: Nice to Have

| Issue | Impact | Effort | Recommendation |
|-------|--------|--------|----------------|
| Code duplication | Low | Low | Extract common RSS aggregation logic |
| Missing indexes | Low | Low | Add indexes for common query patterns |
| ~~Argon2 migration~~ | ~~Low~~ | ~~Medium~~ | ✅ Completed - bcrypt to Argon2id switch |

---

## 8. Missing Features Analysis

### Planned but Not Implemented

Based on `FEATURES.md` and `GOALS.md`:

| Feature | Status | Priority | Notes |
|---------|--------|----------|-------|
| Playlist sync between devices | Not Started | High | TODO in codebase |
| Multi-device real-time sync | Partial | High | WebSocket exists, sync logic incomplete |
| Federation between instances | Not Started | Medium | Vision goal |
| Mobile app SDKs | Not Started | Medium | Needed for integrations |
| Collaborative playlists | Not Started | Low | Future enhancement |
| Advanced recommendations | Not Started | Low | Requires ML infrastructure |

### Sync Controller Gap

The `SyncController` has a critical TODO:

```elixir
# TODO: implémenter selon votre structure
```

This means the core sync functionality is incomplete.

---

## 9. Recommendations Summary

### Immediate Actions (Next Sprint)

1. **Add tests for SyncController** - Core functionality needs coverage
2. **Implement input validation** - Especially for RSS URLs
3. **Add rate limiting** - Use existing Hammer dependency more widely
4. **Fix error handling** - Stop exposing `inspect(reason)`

### Short-term (1-3 Months)

1. **Complete playlist sync** - Address TODO in aggregate
2. **Split User aggregate** - Create bounded contexts
3. **Add property-based tests** - Use StreamData for commands
4. **Implement SSRF protection** - Validate and sanitize URLs

### Long-term (3-6 Months)

1. **Performance testing** - Load test API and projections
2. **Federation protocol** - Design inter-instance communication
3. **SDK development** - Create client libraries for apps
4. **Observability** - Add OpenTelemetry tracing

---

## 10. Architecture Diagrams

### Current System Architecture

```
+-------------------+     +-------------------+
|   Client Apps     |     |   Web Browser     |
| (Podcast Players) |     |   (UI)            |
+--------+----------+     +--------+----------+
         |                         |
         | JWT (RS256)             | Session
         v                         v
+------------------------------------------+
|           BaladosSyncWeb                  |
|  +-------------+  +-------------------+  |
|  | Controllers |  | LiveView/HTML     |  |
|  +------+------+  +--------+----------+  |
+---------|------------------|--------------+
          |                  |
          v                  v
+------------------------------------------+
|           BaladosSyncCore                 |
|  +------------+  +-------------------+   |
|  | Dispatcher |  | User Aggregate    |   |
|  | (Commanded)|  | (execute/apply)   |   |
|  +-----+------+  +--------+----------+   |
|        |                  |              |
|        v                  v              |
|  +-----------------------------------+   |
|  |         EventStore (PG)           |   |
|  +-----------------------------------+   |
+------------------------------------------+
          |
          | Events
          v
+------------------------------------------+
|        BaladosSyncProjections             |
|  +------------+  +-------------------+   |
|  | Projectors |  | Read Models       |   |
|  | (6 total)  |  | (Ecto Schemas)    |   |
|  +-----+------+  +--------+----------+   |
|        |                  |              |
|        v                  v              |
|  +-----------------------------------+   |
|  |    PostgreSQL (public/system)     |   |
|  +-----------------------------------+   |
+------------------------------------------+
          ^
          |
+------------------------------------------+
|          BaladosSyncJobs                  |
|  +------------------+  +---------------+ |
|  | SnapshotWorker   |  | CleanupWorker | |
|  | (Quantum)        |  | (Quantum)     | |
|  +------------------+  +---------------+ |
+------------------------------------------+
```

### CQRS Flow

```
[Command] --> [Dispatcher] --> [Aggregate.execute/2]
                                      |
                                      v
                               [Event emitted]
                                      |
                                      v
                              [EventStore.append]
                                      |
                        +-------------+-------------+
                        |             |             |
                        v             v             v
                  [Projector1]  [Projector2]  [Projector3]
                        |             |             |
                        v             v             v
                    [Table1]      [Table2]      [Table3]
```

---

## Appendix A: File Count by App

| App | Source Files | Test Files |
|-----|--------------|------------|
| balados_sync_core | 31 | 4 |
| balados_sync_projections | 18 | 4 |
| balados_sync_web | 48 | 22 |
| balados_sync_jobs | 4 | 1 |

## Appendix B: Controller Coverage Matrix

| Controller | Lines | Has Tests | Test Count |
|------------|-------|-----------|------------|
| PublicController | 530 | Yes | 5 |
| SubscriptionController | 249 | No | 0 |
| PlaylistsController | ~200 | Yes | 15+ |
| RssAggregateController | 441 | Yes | 8 |
| CollectionsController | ~250 | Yes | 10+ |
| ProfileController | ~150 | Yes | 13 |
| PodcastOwnershipController | ~400 | Yes | 10+ |
| Others (17) | Varies | Mostly No | - |

---

**End of Audit Report**

*Generated by Claude (Opus 4.5) on 2025-12-21*
