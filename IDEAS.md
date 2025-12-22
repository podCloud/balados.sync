# Ideas & Future Features

This document captures ideas for future development, organized by priority and category.

**Last Updated**: 2025-12-22

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
| Split User aggregate | High | Medium | #148 - 1030 lines, multiple bounded contexts |
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
| Collaborative playlists | Multiple users can contribute to a playlist | #153 - Requires permissions model |
| Podcast reviews/ratings | Users can rate and review podcasts | #154 - Privacy considerations |
| Follow other users | See what friends are listening to | #155 - Social graph |
| Trending algorithms | Improve popularity scoring | #156 - Time decay, engagement weights |
| Personalized recommendations | ML-based suggestions | #157 - Requires usage data analysis |
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

### Platform Expansion

| Idea | Description | Notes |
|------|-------------|-------|
| Mobile apps (iOS/Android) | Native apps with offline | #169 - Consider Flutter or native |
| Desktop app (Electron/Tauri) | Cross-platform desktop | #170 - Sync daemon possible |
| Browser extension | Quick subscribe from any page | #171 - Chrome, Firefox, Safari |
| CLI tool | Command-line podcast management | #172 - For power users |
| Apple Watch companion | Quick controls and now playing | #173 - watchOS app |

### Content Features

| Idea | Description | Notes |
|------|-------------|-------|
| Video podcast support | YouTube/video RSS feeds | #174 - Different player UI |
| Transcript search | Full-text search in episodes | #175 - Requires transcription |
| Chapter markers | Native chapter support | #176 - From podcast feed |
| Show notes enhancement | Rich text, links, images | #177 - Parse from RSS |
| Clip creation | Save and share audio clips | #178 - Copyright considerations |

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
| Large User aggregate | `user.ex` (1030 lines) | Medium - #148 |

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

3. **Recommendation Engine** - #180
   - Collaborative filtering
   - Content-based filtering
   - Privacy-preserving recommendations

4. **Transcription Services** - #181
   - Whisper API vs cloud services
   - Cost considerations
   - Storage requirements

---

## Community Requested Features

*(Add features requested by users here)*

- [ ] *No community requests yet - project not public*

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
