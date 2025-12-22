# Subscriptions API

Manage podcast subscriptions for the authenticated user.

## Endpoints

| Method | Path | Description |
|--------|------|-------------|
| `GET` | `/api/v1/subscriptions` | List all subscriptions |
| `POST` | `/api/v1/subscriptions` | Subscribe to a podcast |
| `DELETE` | `/api/v1/subscriptions/:feed` | Unsubscribe from a podcast |
| `GET` | `/api/v1/subscriptions/:feed/metadata` | Get podcast metadata |

## List Subscriptions

```http
GET /api/v1/subscriptions
Authorization: Bearer <token>
```

### Response

```json
{
  "subscriptions": [
    {
      "id": "sub-123",
      "rss_source_feed": "aHR0cHM6Ly9mZWVkcy5leGFtcGxlLmNvbS9wb2RjYXN0",
      "rss_source_id": "podcast-abc",
      "subscribed_at": "2024-01-15T10:30:00Z",
      "metadata": {
        "title": "Example Podcast",
        "description": "A great podcast about examples",
        "image_url": "https://example.com/cover.jpg"
      }
    }
  ]
}
```

## Subscribe to a Podcast

```http
POST /api/v1/subscriptions
Authorization: Bearer <token>
Content-Type: application/json

{
  "feed": "aHR0cHM6Ly9mZWVkcy5leGFtcGxlLmNvbS9wb2RjYXN0"
}
```

### Request Body

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `feed` | string | Yes | Base64-encoded RSS feed URL |

### Response (201 Created)

```json
{
  "subscription": {
    "id": "sub-456",
    "rss_source_feed": "aHR0cHM6Ly9mZWVkcy5leGFtcGxlLmNvbS9wb2RjYXN0",
    "rss_source_id": "podcast-xyz",
    "subscribed_at": "2024-01-20T14:00:00Z"
  }
}
```

### Errors

| Code | Description |
|------|-------------|
| `INVALID_FEED` | The feed URL is malformed or not a valid RSS feed |
| `ALREADY_SUBSCRIBED` | User is already subscribed to this feed |

## Unsubscribe from a Podcast

```http
DELETE /api/v1/subscriptions/:feed
Authorization: Bearer <token>
```

### Path Parameters

| Parameter | Description |
|-----------|-------------|
| `feed` | Base64-encoded RSS feed URL |

### Response (200 OK)

```json
{
  "message": "Unsubscribed successfully"
}
```

## Get Podcast Metadata

Fetch metadata for a subscribed podcast (title, description, episodes).

```http
GET /api/v1/subscriptions/:feed/metadata
Authorization: Bearer <token>
```

### Response

```json
{
  "metadata": {
    "title": "Example Podcast",
    "description": "A great podcast about examples",
    "author": "John Doe",
    "image_url": "https://example.com/cover.jpg",
    "link": "https://example.com",
    "language": "en",
    "episode_count": 42
  }
}
```

## Example: Subscribe with curl

```bash
# Encode the feed URL
FEED=$(echo -n "https://feeds.example.com/podcast.xml" | base64)

# Subscribe
curl -X POST "https://sync.balados.cloud/api/v1/subscriptions" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d "{\"feed\": \"$FEED\"}"
```
