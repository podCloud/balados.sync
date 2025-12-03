# Known Bugs

## 🐛 Episode Metadata Not Enriched from RSS (MINOR)

**Status:** Partially Resolved - 2025-12-03
**Date Reported:** 2025-12-03
**Severity:** Low
**Fixed:** Podcast and episode popularity metrics (plays, scores) ✅

### Description
When a user plays an episode via the Play Gateway link:
- `episode_popularity.episode_title` remains NULL (still unfixed)
- `episode_popularity.podcast_title` remains NULL (still unfixed)
- `podcast_popularity` NOW CORRECTLY updated ✅ (FIXED 2025-12-03)
- `episode_popularity` plays/scores NOW CORRECTLY updated ✅ (FIXED 2025-12-03)

### Root Cause Found and Fixed
The `PopularityProjector` was using `changeset(updated, %{})` with an empty attributes map, which caused Ecto to create an empty changeset with no actual changes to persist. This was fixed by creating proper attributes maps before calling changeset.

**Fixes Applied:**
1. Podcast popularity update (line 108-155): Changed from `changeset(updated, %{})` to proper `attrs` map
2. Episode popularity update (line 157-209): Changed from `changeset(updated, %{})` to proper `attrs` map
3. Metadata enrichment (line 391-427): Added `rss_source_feed` to both struct creation and attrs

### Remaining Issue
Episode metadata (title, author, description, cover, podcast_title) are still not being enriched from RSS feed. This requires investigation into the async Task execution and database persistence within ProjectionsRepo context.

### Current Test Results (After Fix - 2025-12-03)

**Verified Working:**
- Podcast popularity now correctly updated:
  - plays: 0 → 7 ✅
  - score: 10 → 35 ✅
- Episode popularity plays/scores correctly updated:
  - plays: 0 → 7 ✅
  - score: 0 → 35 ✅

**Still Not Working:**
- Async metadata enrichment (episode_title, podcast_title) remains NULL
  - Task.start() executes and logs success, but changes not persisted to DB
  - Requires investigation into async Task context with ProjectionsRepo

### Steps to Reproduce Metadata Issue
1. Play an episode via Play Gateway
2. Check logs: `[PopularityProjector] Metadata enrichment successful: title=...` appears ✓
3. Check database: episode_title and podcast_title still NULL ✗

### Investigation Notes for Metadata
- Async task successfully fetches RSS and finds episode
- Logs show "Metadata enrichment successful"
- changeset appears valid with proper attrs
- `ProjectionsRepo.insert_or_update()` call completes without error
- Yet changes don't appear in database

**Hypothesis:** Async Task.start() may execute in a context where ProjectionsRepo connection or transaction handling is problematic

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
