# Ideas & Future Features

This document captures ideas for future development of **Balados Sync** (backend).

**Last Updated**: 2026-01-09

---

## ⚠️ Scope Reminder

**Balados Sync** = Backend server for sync, storage, and data management

Features that belong here:
- API endpoints and sync logic
- Data storage (subscriptions, plays, playlists, collections)
- RSS export/generation
- Discovery features (timeline, popularity, profiles)
- Web pages for CRUD management
- Infrastructure, federation, SDKs

Features that belong in **Balados App** (separate project):
- Audio/video playback
- Offline support
- Native mobile/desktop apps
- Chapter markers, clip creation
- Any player UI

---

## Priority 1: Critical Path (Next Sprint)

These items address gaps identified in the [architectural audit](docs/ARCHITECTURAL_AUDIT.md).

### Testing & Quality

| Idea | Effort | Impact | Notes |
|------|--------|--------|-------|
| ~~Add tests for SyncController~~ | ~~Medium~~ | ~~High~~ | ✅ #132 - Comprehensive sync tests added |
| ~~Add tests for PlayController~~ | ~~Medium~~ | ~~High~~ | ✅ Already has ~20 tests covering all endpoints |
| ~~Add tests for PrivacyController~~ | ~~Low~~ | ~~Medium~~ | ✅ #127 - Privacy management tested |
| ~~Property-based tests with StreamData~~ | ~~Medium~~ | ~~Medium~~ | ✅ #143 - StreamData tests for commands |

### Security Hardening

| Idea | Effort | Impact | Notes |
|------|--------|--------|-------|
| ~~Input validation for RSS URLs~~ | ~~Low~~ | ~~High~~ | ✅ #122 - SSRF prevention |
| ~~Rate limiting on API endpoints~~ | ~~Low~~ | ~~High~~ | ✅ #123 - Hammer usage extended |
| ~~Sanitize error messages~~ | ~~Low~~ | ~~Medium~~ | ✅ #124 - ErrorHelpers module |
| ~~Request body size limits~~ | ~~Low~~ | ~~Medium~~ | ✅ #133 - 1MB limit in Plug.Parsers |

---

## Priority 2: Short-term Improvements (1-3 Months)

### Core Features

| Idea | Effort | Impact | Notes |
|------|--------|--------|-------|
| ~~Complete playlist sync~~ | ~~High~~ | ~~High~~ | ✅ #131 - Implemented direct projection merge |
| ~~Multi-device real-time sync~~ | ~~High~~ | ~~High~~ | ✅ #145 - Complete sync with conflict resolution |
| ~~Conflict resolution strategy~~ | ~~Medium~~ | ~~High~~ | ✅ #145 - Last-write-wins with version vectors |
| Offline-first support | High | Medium | #152 - Important for mobile apps |

### Architecture

| Idea | Effort | Impact | Notes |
|------|--------|--------|-------|
| ~~Split User aggregate~~ | ~~High~~ | ~~Medium~~ | ✅ #148 / PR #238 - Split into 4 bounded context aggregates (Subscription, PlayTracking, Playlist, Collection) |
| Extract RSS infrastructure | Medium | Low | #149 - Move from core to infra layer |
| ~~Centralized error handling~~ | ~~Medium~~ | ~~Medium~~ | ✅ #124 - ErrorHelpers module created |
| ~~Add missing DB indexes~~ | ~~Low~~ | ~~Low~~ | ✅ Indexes already exist in migrations |

### Developer Experience

| Idea | Effort | Impact | Notes |
|------|--------|--------|-------|
| ~~API documentation (ExDoc)~~ | ~~Medium~~ | ~~High~~ | ✅ #144 - Comprehensive ExDoc guides |
| Client SDKs (JS, Swift, Kotlin) | High | High | #150 - Easier app integration |
| Postman/Insomnia collection | Low | Medium | #151 - Quick testing for devs |
| ~~Better error codes~~ | ~~Low~~ | ~~Medium~~ | ✅ #136 - Added error_code field to all API errors |

---

## Priority 3: Medium-term Features (3-6 Months)

### Discovery & Social

| Idea | Description | Notes |
|------|-------------|-------|
| Collaborative playlists | Multiple users can contribute to a playlist | [#153](https://github.com/podCloud/balados.sync/issues/153) - Requires permissions model |
| Listening history page | Detailed history with filters and stats | [#200](https://github.com/podCloud/balados.sync/issues/200) - Privacy-respecting |
| Discovery + Recommendations | Trending, search, MinHash recommendations | [#201](https://github.com/podCloud/balados.sync/issues/201) - Comprehensive discovery |
| ~~Podcast likes~~ | ~~Users can like podcasts and episodes~~ | ✅ #154 / PR #255 - Implemented |
| Podcast reviews/ratings | Users can rate and review podcasts | #261 - Privacy considerations |
| Follow other users | See what friends are listening to | #155 - Social graph |
| Hashtags/topics | Categorize podcasts by topic | #158 - User-generated taxonomy |

### Federation

| Idea | Description | Notes |
|------|-------------|-------|
| ActivityPub protocol | Standard federation protocol | #159 - Complex but powerful |
| Instance discovery | Find other Balados instances | #163 - DNS-based or registry |
| Cross-instance following | Follow users on other instances | #160 - Privacy implications |
| Federated timeline | Aggregate from multiple instances | #161 - Performance concerns |
| Instance statistics sharing | Share anonymized stats | #162 - Opt-in for privacy |

### Infrastructure

| Idea | Description | Notes |
|------|-------------|-------|
| OpenTelemetry tracing | Full request tracing | #164 - Critical for debugging |
| Prometheus metrics | System health monitoring | #165 - Dashboard with Grafana |
| Load testing suite | Verify scalability | #166 - k6 or similar |
| Blue/green deployments | Zero-downtime updates | #167 - Infrastructure automation |
| Database read replicas | Scale read operations | #168 - For high traffic |

---

## Priority 4: Long-term Vision (6+ Months)

### Platform Integration (Sync-side)

| Idea | Description | Notes |
|------|-------------|-------|
| Browser extension | Quick subscribe button from any page | #171 - Adds feed to Sync |
| CLI tool | Command-line sync data management | #172 - For power users |

### Content Metadata (stored in Sync)

| Idea | Description | Notes |
|------|-------------|-------|
| Transcript storage | Store transcripts for search | #175 - Requires transcription service |
| Show notes enhancement | Parse and store rich metadata | #177 - From RSS parsing |

### Monetization (Optional)

| Idea | Description | Notes |
|------|-------------|-------|
| Podcast creator tools | Analytics for podcasters | Aggregate listener data |
| Premium features | Extended storage, priority sync | Freemium model |
| Self-hosted licenses | Commercial support option | For enterprises |

---

## Technical Debt Backlog

Items from code analysis that should be addressed:

| Item | Location | Priority |
|------|----------|----------|
| ~~TODO: implement sync structure~~ | ~~`sync_controller.ex:64`~~ | ~~High~~ ✅ #131 |
| ~~TODO: playlists documentation~~ | ~~`user.ex:25`~~ | ~~Low~~ ✅ #131 |
| ~~TODO: Sync playlists not implemented~~ | ~~`user.ex:349`~~ | ~~High~~ ✅ #131 |
| ~~TODO: Switch to Argon2~~ | ~~`user.ex:88`~~ | ~~Medium~~ ✅ #142 |
| TODO: EventStore API simplification | `snapshot_worker.ex:38` | Low - #146 |
| Duplicate code in RSS aggregation | `rss_aggregate_controller.ex` | Low - #147 |
| ~~Large User aggregate~~ | ~~`user.ex` (1030 lines)~~ | ✅ #148 / PR #238 - Split into 4 aggregates |

---

## Research Topics

Areas that need investigation before implementation:

1. **Federation Protocol Selection** - #179
   - ActivityPub vs custom protocol
   - Privacy in federated systems
   - Conflict resolution across instances

2. ~~**Real-time Sync Architecture**~~ ✅ #145
   - ~~CRDTs for conflict-free sync~~
   - ~~Operational transforms~~
   - ~~Last-write-wins vs merge strategies~~ → Implemented LWW with version vectors

3. ~~**Recommendation Engine**~~ → Superseded by [#201](https://github.com/podCloud/balados.sync/issues/201)
   - ~~Collaborative filtering~~ → MinHash/LSH approach designed
   - ~~Content-based filtering~~
   - ~~Privacy-preserving recommendations~~ → Public subscriptions only

4. **Transcription Services** - #181
   - Whisper API vs cloud services
   - Cost considerations
   - Storage requirements

---

## Community Requested Features

*(Add features requested by users here)*

- [ ] *No community requests yet - project not public*

---

## Out of Scope (→ Balados App)

These features belong in the **Balados App** frontend project, not in Sync:

| Idea | Description | Issue | Reason |
|------|-------------|-------|--------|
| Mobile apps (iOS/Android) | Native apps with offline | #169 | Player/app feature |
| Desktop app (Electron/Tauri) | Cross-platform desktop | #170 | Player/app feature |
| Apple Watch companion | Quick controls and now playing | #173 | Player/app feature |
| Video podcast support | YouTube/video RSS player | #174 | Player feature |
| Chapter markers | Native chapter playback | #176 | Player feature |
| Clip creation | Save and share audio clips | #178 | Player feature |
| Offline-first support | Local storage for mobile | #152 | App feature |

---

## Rejected Ideas

Ideas considered but not pursuing:

| Idea | Reason for Rejection |
|------|---------------------|
| Cryptocurrency integration | Against project philosophy |
| Advertising platform | Privacy-first approach |
| Exclusive content hosting | Focus on RSS aggregation |

---

## How to Contribute Ideas

1. Open a GitHub issue with the `idea` label
2. Describe the feature and its value
3. Consider privacy and architectural implications
4. Reference this document if applicable

---

**Note**: This document is a living roadmap. Items may be reprioritized based on:
- User feedback
- Technical dependencies
- Resource availability
- Strategic direction changes
