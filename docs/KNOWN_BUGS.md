# Known Bugs

## 🐛 Unknown Episode in Play Gateway (CRITICAL)

**Status:** Open - Not yet resolved
**Date Reported:** 2025-12-03
**Severity:** High

### Description
When a user plays an episode via the Play Gateway link, the episode appears as "unknown episode" in the UI. Additionally:
- `episode_popularity.episode_title` remains NULL
- `podcast_popularity` is NOT updated (plays = 0, score unchanged)
- Only `episode_popularity` gets updated with plays count and score

### Expected Behavior
- Episode title should be fetched from RSS and stored in `episode_popularity.episode_title`
- Podcast title should be stored in `episode_popularity.podcast_title`
- `podcast_popularity` should be incremented (plays + 1, score + 5)

### Actual Behavior
- Episode displays as "unknown episode"
- Episode metadata NOT enriched from RSS
- Podcast popularity metrics NOT updated

### Investigation Details

**Code Changes Made (2025-12-03):**
1. Moved `RssCache` and `RssParser` from `balados_sync_web` to `balados_sync_core`
2. Added async metadata enrichment in `PopularityProjector.enrich_episode_metadata_async/2`
3. Added extensive logging to `PopularityProjector` to trace execution:
   - Logs for PlayRecorded event reception
   - Logs for podcast_popularity update attempt
   - Logs for episode_popularity update attempt
   - Logs for async metadata enrichment
   - Full exception details in rescue blocks
4. Added `podcast_title` field to `EpisodePopularity` schema

**Event Flow Analysis:**
```
PlayRecorded Event (decoded from Base64)
├── Feed: https://decouvrez.lepodcast.fr/rss
├── Item GUID: 65423905453819671ff3ddf6
├── Enclosure: https://stats.podcloud.fr/decouvrez/cetait-mieux-avant/...
│
├── PopularityProjector:podcast_popularity -> SHOULD update (but doesn't)
├── PopularityProjector:episode_popularity -> Updates plays=1, score=5 ✓
└── PopularityProjector:enrich_metadata -> Async RSS fetch (TODO: verify)
```

**Database State (Last Known):**
```sql
-- podcast_popularity (NOT UPDATED)
plays = 0, score = 10 (only from subscription)

-- episode_popularity (UPDATED)
plays = 1, score = 5, episode_title = NULL ✗
```

**Logs Added (for debugging):**
- `[PopularityProjector] PlayRecorded event: user=..., feed=..., item=...`
- `[PopularityProjector] Processing podcast popularity for feed: ...`
- `[PopularityProjector] Current podcast popularity: plays=..., score=...`
- `[PopularityProjector] Updated podcast popularity: plays=..., score=...`
- `[PopularityProjector] Podcast popularity updated successfully: plays=..., score=...`
- `[PopularityProjector] Processing episode popularity for item: ...`
- `[PopularityProjector] Starting async metadata enrichment for item: ...`
- `[PopularityProjector] Enriching metadata: feed=..., item=...`
- `[PopularityProjector] Found episode: title=...` (if found)

### Steps to Reproduce
1. Log in to web interface
2. Subscribe to podcast: https://decouvrez.lepodcast.fr/rss
3. Click on a feed episode to view details
4. Click "Écouter" (play button) which links to play gateway
5. Observe episode displays as "unknown episode"
6. Check database:
   ```sql
   SELECT episode_title, podcast_title, plays FROM episode_popularity WHERE rss_source_item = '...';
   SELECT plays, score FROM podcast_popularity WHERE rss_source_feed = '...';
   ```

### Possible Root Causes
1. **Projector Transaction Failure**: `Ecto.Multi.run` for podcast_popularity may be failing silently
2. **Event Projection Lag**: Projector may not have reprocessed events after code changes
3. **RSS Fetch Timeout**: Async enrichment may be timing out when fetching RSS
4. **Base64 Decoding Issue**: Episode item IDs may not be decoding correctly
5. **Database Constraint**: Episode_popularity update may be blocking podcast_popularity update

### Workarounds
- None currently available

### Next Steps
1. **Check Projector Logs**: Monitor application logs for any ERROR or WARNING messages from PopularityProjector
2. **Manually Reset Projector**: Reset `projection_versions.last_seen_event_number` to 0 for PopularityProjector to force reprocessing
3. **Test with New Play**: After reset, trigger a new play and check logs
4. **Verify RSS Cache**: Ensure RssCache.fetch_and_parse_feed() is working correctly
5. **Add Unit Tests**: Create tests for PopularityProjector.project/3 callback with PlayRecorded events

### Related Files
- `/apps/balados_sync_projections/lib/balados_sync_projections/projectors/popularity_projector.ex` (100+)
- `/apps/balados_sync_core/lib/balados_sync_core/rss_cache.ex` (new)
- `/apps/balados_sync_core/lib/balados_sync_core/rss_parser.ex` (moved from web)
- `/apps/balados_sync_projections/lib/balados_sync_projections/schemas/episode_popularity.ex`

### Environment
- Elixir 1.15.0
- Postgres 14+
- Eventstore 1.4
- Commanded 1.4
- Last tested: 2025-12-03 after server restart
