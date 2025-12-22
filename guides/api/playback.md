# Playback API

Record and synchronize podcast playback progress across devices.

## Endpoints

| Method | Path | Description |
|--------|------|-------------|
| `GET` | `/api/v1/play` | Get playback status for all episodes |
| `POST` | `/api/v1/play` | Record a play event |
| `PUT` | `/api/v1/play/:item/position` | Update playback position |

## Get Playback Status

Retrieve the playback status for all episodes the user has listened to.

```http
GET /api/v1/play
Authorization: Bearer <token>
```

### Query Parameters

| Parameter | Type | Description |
|-----------|------|-------------|
| `feed` | string | (Optional) Filter by Base64-encoded feed URL |
| `since` | string | (Optional) ISO 8601 timestamp to get updates since |

### Response

```json
{
  "plays": [
    {
      "rss_source_feed": "aHR0cHM6Ly9mZWVkcy5leGFtcGxlLmNvbS9wb2RjYXN0",
      "rss_source_item": "Z3VpZC0xMjMsaHR0cHM6Ly9leGFtcGxlLmNvbS9lcGlzb2RlLm1wMw==",
      "position": 1234,
      "played": false,
      "updated_at": "2024-01-20T15:30:00Z"
    },
    {
      "rss_source_feed": "aHR0cHM6Ly9mZWVkcy5leGFtcGxlLmNvbS9wb2RjYXN0",
      "rss_source_item": "Z3VpZC00NTYsaHR0cHM6Ly9leGFtcGxlLmNvbS9lcGlzb2RlMi5tcDM=",
      "position": 3600,
      "played": true,
      "updated_at": "2024-01-19T10:00:00Z"
    }
  ]
}
```

## Record a Play Event

Record that the user played an episode, with optional position and completion status.

```http
POST /api/v1/play
Authorization: Bearer <token>
Content-Type: application/json

{
  "feed": "aHR0cHM6Ly9mZWVkcy5leGFtcGxlLmNvbS9wb2RjYXN0",
  "item": "Z3VpZC0xMjMsaHR0cHM6Ly9leGFtcGxlLmNvbS9lcGlzb2RlLm1wMw==",
  "position": 1234,
  "played": false
}
```

### Request Body

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `feed` | string | Yes | Base64-encoded RSS feed URL |
| `item` | string | Yes | Base64-encoded episode identifier (`guid,enclosure_url`) |
| `position` | integer | No | Playback position in seconds (default: 0) |
| `played` | boolean | No | Whether episode is completed (default: false) |

### Response (201 Created)

```json
{
  "play": {
    "rss_source_feed": "aHR0cHM6Ly9mZWVkcy5leGFtcGxlLmNvbS9wb2RjYXN0",
    "rss_source_item": "Z3VpZC0xMjMsaHR0cHM6Ly9leGFtcGxlLmNvbS9lcGlzb2RlLm1wMw==",
    "position": 1234,
    "played": false,
    "recorded_at": "2024-01-20T15:30:00Z"
  }
}
```

## Update Playback Position

Update just the playback position for an episode (lighter than full record).

```http
PUT /api/v1/play/:item/position
Authorization: Bearer <token>
Content-Type: application/json

{
  "position": 2500
}
```

### Path Parameters

| Parameter | Description |
|-----------|-------------|
| `item` | Base64-encoded episode identifier |

### Request Body

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `position` | integer | Yes | New playback position in seconds |

### Response (200 OK)

```json
{
  "position": 2500,
  "updated_at": "2024-01-20T15:35:00Z"
}
```

## Episode Identifier Format

Episode identifiers are Base64-encoded strings containing the episode GUID and enclosure URL:

```
guid,enclosure_url
```

Example:
```elixir
# Original
"episode-123,https://example.com/episode.mp3"

# Base64 encoded
"ZXBpc29kZS0xMjMsaHR0cHM6Ly9leGFtcGxlLmNvbS9lcGlzb2RlLm1wMw=="
```

## Example: Sync Playback with curl

```bash
# Encode feed and episode
FEED=$(echo -n "https://feeds.example.com/podcast.xml" | base64)
ITEM=$(echo -n "ep-123,https://example.com/ep123.mp3" | base64)

# Record play at position 5 minutes
curl -X POST "https://sync.balados.cloud/api/v1/play" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d "{\"feed\": \"$FEED\", \"item\": \"$ITEM\", \"position\": 300}"
```
