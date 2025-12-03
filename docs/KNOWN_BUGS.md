# Known Bugs

*(No active bugs - all issues resolved as of 2025-12-03)*

## ✅ RESOLVED: Unknown Episode in Play Gateway

**Status:** FIXED - 2025-12-03
**Date Reported:** 2025-12-03
**Severity:** Was High - Now Resolved

### What Was Fixed
When a user played an episode via Play Gateway:
- `podcast_popularity` updates: plays and score now correctly increment ✅
- `episode_popularity` updates: plays and score now correctly increment ✅
- `episode_popularity.episode_title`: Now enriched from RSS ✅
- `episode_popularity.podcast_title`: Now enriched from RSS ✅
- `episode_popularity.episode_cover`: Now enriched from RSS ✅

### Root Causes Found and Fixed

**Issue 1: Empty Changeset Maps**
- The `PopularityProjector` was using `changeset(updated, %{})` with empty attribute maps
- This caused Ecto to create changesets with no actual changes
- **Fix**: Created proper `attrs` maps before calling changeset
- **Result**: Both podcast and episode popularity metrics now persist correctly

**Issue 2: Cover Format Mismatch**
- RssParser returns `episode.cover` as a string URL
- EpisodePopularity schema expects `episode_cover` as a map `{src, srcset}`
- **Fix**: Convert string URL to proper map format before changeset
- **Result**: All metadata fields now enrich and persist correctly

### Test Results
- Podcast popularity: plays 0→9, score 10→45 ✅
- Episode popularity: plays 0→9, score 0→45 ✅
- Episode title: "C´était mieux avant" ✅
- Podcast title: "Découvrez, le Podcast" ✅
- Episode cover: Enriched from RSS ✅

### Related Files
- `/apps/balados_sync_projections/lib/balados_sync_projections/projectors/popularity_projector.ex`
- `/apps/balados_sync_core/lib/balados_sync_core/rss_cache.ex`
- `/apps/balados_sync_core/lib/balados_sync_core/rss_parser.ex`
- `/apps/balados_sync_projections/lib/balados_sync_projections/schemas/episode_popularity.ex`
