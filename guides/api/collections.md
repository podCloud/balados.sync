# Collections API

Organize podcasts into collections (folders/groups).

## Endpoints

| Method | Path | Description |
|--------|------|-------------|
| `GET` | `/api/v1/collections` | List all collections |
| `GET` | `/api/v1/collections/:id` | Get a collection |
| `POST` | `/api/v1/collections` | Create a collection |
| `PATCH` | `/api/v1/collections/:id` | Update a collection |
| `DELETE` | `/api/v1/collections/:id` | Delete a collection |
| `POST` | `/api/v1/collections/:id/feeds` | Add a feed to collection |
| `DELETE` | `/api/v1/collections/:id/feeds/:feed_id` | Remove feed from collection |

## List Collections

```http
GET /api/v1/collections
Authorization: Bearer <token>
```

### Response

```json
{
  "collections": [
    {
      "id": "col-123",
      "name": "Tech Podcasts",
      "description": "My favorite tech shows",
      "is_public": false,
      "feeds": [
        {
          "id": "feed-1",
          "rss_source_feed": "aHR0cHM6Ly9mZWVkcy5leGFtcGxlLmNvbS90ZWNo",
          "position": 0
        }
      ],
      "created_at": "2024-01-10T09:00:00Z",
      "updated_at": "2024-01-15T14:00:00Z"
    }
  ]
}
```

## Get a Collection

```http
GET /api/v1/collections/:id
Authorization: Bearer <token>
```

### Response

```json
{
  "collection": {
    "id": "col-123",
    "name": "Tech Podcasts",
    "description": "My favorite tech shows",
    "is_public": false,
    "feeds": [
      {
        "id": "feed-1",
        "rss_source_feed": "aHR0cHM6Ly9mZWVkcy5leGFtcGxlLmNvbS90ZWNo",
        "position": 0,
        "metadata": {
          "title": "Tech Talk",
          "image_url": "https://example.com/tech.jpg"
        }
      }
    ],
    "created_at": "2024-01-10T09:00:00Z"
  }
}
```

## Create a Collection

```http
POST /api/v1/collections
Authorization: Bearer <token>
Content-Type: application/json

{
  "name": "Comedy Shows",
  "description": "Podcasts that make me laugh",
  "is_public": false
}
```

### Request Body

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `name` | string | Yes | Collection name (max 100 chars) |
| `description` | string | No | Collection description (max 500 chars) |
| `is_public` | boolean | No | Make collection publicly visible (default: false) |

### Response (201 Created)

```json
{
  "collection": {
    "id": "col-456",
    "name": "Comedy Shows",
    "description": "Podcasts that make me laugh",
    "is_public": false,
    "feeds": [],
    "created_at": "2024-01-20T10:00:00Z"
  }
}
```

## Update a Collection

```http
PATCH /api/v1/collections/:id
Authorization: Bearer <token>
Content-Type: application/json

{
  "name": "Comedy & Humor",
  "is_public": true
}
```

### Request Body

All fields are optional. Only provided fields will be updated.

| Field | Type | Description |
|-------|------|-------------|
| `name` | string | New collection name |
| `description` | string | New description |
| `is_public` | boolean | Update visibility |

### Response (200 OK)

```json
{
  "collection": {
    "id": "col-456",
    "name": "Comedy & Humor",
    "description": "Podcasts that make me laugh",
    "is_public": true,
    "updated_at": "2024-01-20T11:00:00Z"
  }
}
```

## Delete a Collection

```http
DELETE /api/v1/collections/:id
Authorization: Bearer <token>
```

### Response (200 OK)

```json
{
  "message": "Collection deleted"
}
```

## Add Feed to Collection

```http
POST /api/v1/collections/:id/feeds
Authorization: Bearer <token>
Content-Type: application/json

{
  "feed": "aHR0cHM6Ly9mZWVkcy5leGFtcGxlLmNvbS9jb21lZHk="
}
```

### Request Body

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `feed` | string | Yes | Base64-encoded RSS feed URL |

### Response (201 Created)

```json
{
  "feed": {
    "id": "feed-789",
    "rss_source_feed": "aHR0cHM6Ly9mZWVkcy5leGFtcGxlLmNvbS9jb21lZHk=",
    "position": 1
  }
}
```

## Remove Feed from Collection

```http
DELETE /api/v1/collections/:id/feeds/:feed_id
Authorization: Bearer <token>
```

### Response (200 OK)

```json
{
  "message": "Feed removed from collection"
}
```

## RSS Feed for Collection

Public collections have an RSS feed that aggregates all podcasts:

```
GET /rss/:user_token/collections/:collection_id
```

This returns an RSS/XML feed with recent episodes from all podcasts in the collection.
