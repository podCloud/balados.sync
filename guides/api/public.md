# Public API

Public endpoints for podcast discovery and trending content. No authentication required.

## Base URL

```
https://sync.balados.cloud/api/v1/public
```

## Endpoints

| Method | Path | Description |
|--------|------|-------------|
| `GET` | `/trending/podcasts` | Get trending podcasts |
| `GET` | `/trending/episodes` | Get trending episodes |
| `GET` | `/timeline` | Get public activity timeline |
| `GET` | `/feed/:feed/popularity` | Get podcast popularity stats |
| `GET` | `/episode/:item/popularity` | Get episode popularity stats |

## Trending Podcasts

Get the most popular podcasts based on subscriber count and recent activity.

```http
GET /api/v1/public/trending/podcasts
```

### Query Parameters

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `limit` | integer | 20 | Number of results (max 100) |
| `period` | string | `week` | Time period: `day`, `week`, `month` |

### Response

```json
{
  "podcasts": [
    {
      "rss_source_feed": "aHR0cHM6Ly9mZWVkcy5leGFtcGxlLmNvbS90b3A=",
      "title": "Top Podcast",
      "description": "The most popular show",
      "image_url": "https://example.com/cover.jpg",
      "subscriber_count": 1234,
      "play_count": 5678,
      "rank": 1
    }
  ],
  "period": "week",
  "generated_at": "2024-01-20T12:00:00Z"
}
```

## Trending Episodes

Get the most played episodes recently.

```http
GET /api/v1/public/trending/episodes
```

### Query Parameters

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `limit` | integer | 20 | Number of results (max 100) |
| `period` | string | `week` | Time period: `day`, `week`, `month` |

### Response

```json
{
  "episodes": [
    {
      "rss_source_feed": "aHR0cHM6Ly9mZWVkcy5leGFtcGxlLmNvbS9wb2RjYXN0",
      "rss_source_item": "Z3VpZC0xMjMsaHR0cHM6Ly9leGFtcGxlLmNvbS9lcDEubXAz",
      "title": "Amazing Episode #42",
      "podcast_title": "Great Podcast",
      "image_url": "https://example.com/ep42.jpg",
      "play_count": 890,
      "completion_rate": 0.75,
      "rank": 1
    }
  ]
}
```

## Public Timeline

Get a feed of public activity (plays, subscriptions) from users who opted in.

```http
GET /api/v1/public/timeline
```

### Query Parameters

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `limit` | integer | 50 | Number of events (max 100) |
| `before` | string | - | Cursor for pagination (event ID) |
| `type` | string | - | Filter by event type: `play`, `subscribe` |

### Response

```json
{
  "events": [
    {
      "id": "evt-123",
      "type": "play",
      "user": {
        "username": "podcast_lover",
        "avatar_url": "https://example.com/avatar.jpg"
      },
      "podcast": {
        "title": "Great Podcast",
        "image_url": "https://example.com/cover.jpg"
      },
      "episode": {
        "title": "Episode 42"
      },
      "timestamp": "2024-01-20T11:30:00Z"
    },
    {
      "id": "evt-122",
      "type": "subscribe",
      "user": {
        "username": "new_listener"
      },
      "podcast": {
        "title": "Another Podcast"
      },
      "timestamp": "2024-01-20T11:25:00Z"
    }
  ],
  "next_cursor": "evt-100"
}
```

## Podcast Popularity

Get detailed popularity statistics for a specific podcast.

```http
GET /api/v1/public/feed/:feed/popularity
```

### Path Parameters

| Parameter | Description |
|-----------|-------------|
| `feed` | Base64-encoded RSS feed URL |

### Response

```json
{
  "rss_source_feed": "aHR0cHM6Ly9mZWVkcy5leGFtcGxlLmNvbS9wb2RjYXN0",
  "subscriber_count": 1234,
  "total_plays": 56789,
  "avg_completion_rate": 0.72,
  "trending_rank": 5,
  "stats_by_period": {
    "day": {"plays": 150, "new_subscribers": 10},
    "week": {"plays": 890, "new_subscribers": 45},
    "month": {"plays": 3200, "new_subscribers": 180}
  }
}
```

## Episode Popularity

Get popularity statistics for a specific episode.

```http
GET /api/v1/public/episode/:item/popularity
```

### Path Parameters

| Parameter | Description |
|-----------|-------------|
| `item` | Base64-encoded episode identifier |

### Response

```json
{
  "rss_source_item": "Z3VpZC0xMjMsaHR0cHM6Ly9leGFtcGxlLmNvbS9lcDEubXAz",
  "play_count": 890,
  "unique_listeners": 654,
  "completion_rate": 0.75,
  "avg_position": 2400,
  "shares": 23
}
```

## Example: Fetch Trending for App Homepage

```bash
# Get top 10 podcasts this week
curl "https://sync.balados.cloud/api/v1/public/trending/podcasts?limit=10&period=week"

# Get recent public activity
curl "https://sync.balados.cloud/api/v1/public/timeline?limit=20"
```

## Privacy Note

Only activity from users who have set their privacy to `public` appears in the public API. Users can control their visibility in their privacy settings.
