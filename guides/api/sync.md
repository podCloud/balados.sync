# Sync API

Full state synchronization endpoint for podcast apps.

## Overview

The sync endpoint allows apps to:
1. Send local changes to the server
2. Receive remote changes since last sync
3. Resolve conflicts between devices

## Endpoint

```http
POST /api/v1/sync
Authorization: Bearer <token>
Content-Type: application/json
```

## Request Format

```json
{
  "last_sync": "2024-01-19T10:00:00Z",
  "changes": {
    "subscriptions": {
      "added": [
        {
          "feed": "aHR0cHM6Ly9mZWVkcy5leGFtcGxlLmNvbS9uZXc=",
          "timestamp": "2024-01-20T08:00:00Z"
        }
      ],
      "removed": [
        {
          "feed": "aHR0cHM6Ly9mZWVkcy5leGFtcGxlLmNvbS9vbGQ=",
          "timestamp": "2024-01-20T09:00:00Z"
        }
      ]
    },
    "plays": [
      {
        "feed": "aHR0cHM6Ly9mZWVkcy5leGFtcGxlLmNvbS9wb2RjYXN0",
        "item": "Z3VpZC0xMjMsaHR0cHM6Ly9leGFtcGxlLmNvbS9lcDEubXAz",
        "position": 1500,
        "played": false,
        "timestamp": "2024-01-20T10:30:00Z"
      }
    ],
    "playlists": [
      {
        "id": "playlist-local-123",
        "name": "Road Trip",
        "items": ["item1", "item2"],
        "timestamp": "2024-01-20T07:00:00Z"
      }
    ]
  }
}
```

### Request Body

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `last_sync` | string | No | ISO 8601 timestamp of last successful sync |
| `changes` | object | Yes | Local changes to push |
| `changes.subscriptions` | object | No | Subscription changes |
| `changes.plays` | array | No | Playback updates |
| `changes.playlists` | array | No | Playlist changes |

## Response Format

```json
{
  "sync_token": "2024-01-20T10:35:00Z",
  "changes": {
    "subscriptions": {
      "added": [
        {
          "feed": "aHR0cHM6Ly9mZWVkcy5leGFtcGxlLmNvbS9mcm9tLW90aGVyLWRldmljZQ==",
          "subscribed_at": "2024-01-19T15:00:00Z"
        }
      ],
      "removed": []
    },
    "plays": [
      {
        "feed": "aHR0cHM6Ly9mZWVkcy5leGFtcGxlLmNvbS9wb2RjYXN0",
        "item": "Z3VpZC00NTYsaHR0cHM6Ly9leGFtcGxlLmNvbS9lcDIubXAz",
        "position": 2400,
        "played": true,
        "updated_at": "2024-01-19T20:00:00Z"
      }
    ],
    "playlists": []
  },
  "conflicts": []
}
```

### Response Fields

| Field | Type | Description |
|-------|------|-------------|
| `sync_token` | string | Token for next sync (use as `last_sync`) |
| `changes` | object | Remote changes since `last_sync` |
| `conflicts` | array | Conflicts that need resolution |

## Conflict Resolution

When the same resource was modified on multiple devices, conflicts are reported:

```json
{
  "conflicts": [
    {
      "type": "play_position",
      "feed": "aHR0cHM6Ly9mZWVkcy5leGFtcGxlLmNvbS9wb2RjYXN0",
      "item": "Z3VpZC0xMjMsaHR0cHM6Ly9leGFtcGxlLmNvbS9lcDEubXAz",
      "local": {
        "position": 1500,
        "timestamp": "2024-01-20T10:30:00Z"
      },
      "remote": {
        "position": 2000,
        "timestamp": "2024-01-20T10:25:00Z"
      },
      "resolution": "local_wins"
    }
  ]
}
```

### Resolution Strategies

| Strategy | Description |
|----------|-------------|
| `local_wins` | Local change was applied |
| `remote_wins` | Remote change takes precedence |
| `merged` | Changes were merged |

**Default behavior**:
- Subscriptions: Last-write-wins
- Play positions: Highest-progress-wins (furthest position)
- Playlists: Merge items, last-write-wins for metadata

## WebSocket Real-Time Sync

For real-time synchronization, connect to the WebSocket endpoint:

```
wss://sync.balados.cloud/api/v1/live
```

### Connection

```javascript
const ws = new WebSocket('wss://sync.balados.cloud/api/v1/live');

ws.onopen = () => {
  // Authenticate
  ws.send(JSON.stringify({
    type: 'auth',
    token: 'your-jwt-token'
  }));
};

ws.onmessage = (event) => {
  const data = JSON.parse(event.data);
  // Handle: auth_success, play_update, subscription_update, etc.
};
```

### Message Types

| Type | Direction | Description |
|------|-----------|-------------|
| `auth` | Client → Server | Authenticate connection |
| `auth_success` | Server → Client | Authentication confirmed |
| `record_play` | Client → Server | Record playback event |
| `play_update` | Server → Client | Playback updated (from another device) |
| `subscribe` | Client → Server | Subscribe to feed |
| `subscription_update` | Server → Client | Subscription changed |

## Example: Full Sync Flow

```bash
# Initial sync (no last_sync, get everything)
curl -X POST "https://sync.balados.cloud/api/v1/sync" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"changes": {}}'

# Response includes sync_token: "2024-01-20T10:00:00Z"

# Subsequent sync with changes
curl -X POST "https://sync.balados.cloud/api/v1/sync" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "last_sync": "2024-01-20T10:00:00Z",
    "changes": {
      "plays": [{
        "feed": "...",
        "item": "...",
        "position": 300
      }]
    }
  }'
```
