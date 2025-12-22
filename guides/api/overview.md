# Balados Sync API

Balados Sync provides a REST API for podcast synchronization across devices and applications.

## Base URL

```
https://sync.balados.cloud/api/v1
```

## Authentication

All API endpoints (except public endpoints) require JWT authentication.

### Obtaining a Token

1. Register your application at `/app-creator`
2. Redirect users to `/authorize?client_id=YOUR_APP_ID&scopes=user.subscriptions.read,user.plays.write`
3. After authorization, receive a JWT token
4. Include the token in all requests: `Authorization: Bearer <token>`

### Token Scopes

| Scope | Description |
|-------|-------------|
| `*` | Full access |
| `*.read` | Read-only access to all resources |
| `*.write` | Write access to all resources |
| `user.subscriptions.read` | Read user's podcast subscriptions |
| `user.subscriptions.write` | Manage subscriptions |
| `user.plays.read` | Read playback history |
| `user.plays.write` | Record playback events |
| `user.playlists.read` | Read playlists |
| `user.playlists.write` | Manage playlists |
| `user.privacy.read` | Read privacy settings |
| `user.privacy.write` | Update privacy settings |
| `user.sync` | Full sync access |

## Error Handling

All errors return a consistent JSON format:

```json
{
  "error": {
    "code": "INVALID_FEED",
    "message": "The RSS feed URL is malformed"
  }
}
```

### Common Error Codes

| Code | HTTP Status | Description |
|------|-------------|-------------|
| `UNAUTHORIZED` | 401 | Missing or invalid authentication |
| `FORBIDDEN` | 403 | Insufficient permissions |
| `NOT_FOUND` | 404 | Resource not found |
| `INVALID_INPUT` | 422 | Validation error |
| `INVALID_FEED` | 422 | Malformed RSS feed URL |
| `RATE_LIMITED` | 429 | Too many requests |
| `SERVER_ERROR` | 500 | Internal server error |

## Rate Limiting

- **Default**: 100 requests per minute per IP
- **Authenticated**: 1000 requests per minute per user
- Headers: `X-RateLimit-Limit`, `X-RateLimit-Remaining`, `X-RateLimit-Reset`

## Data Encoding

RSS feed URLs and episode identifiers are **Base64-encoded** in API requests and responses.

```elixir
# Encode
feed_id = Base.encode64("https://example.com/feed.xml")
# => "aHR0cHM6Ly9leGFtcGxlLmNvbS9mZWVkLnhtbA=="

# Decode
Base.decode64!("aHR0cHM6Ly9leGFtcGxlLmNvbS9mZWVkLnhtbA==")
# => "https://example.com/feed.xml"
```

## Next Steps

- [Subscriptions API](subscriptions.md) - Manage podcast subscriptions
- [Playback API](playback.md) - Record and sync playback progress
- [Collections API](collections.md) - Organize podcasts into collections
- [Sync API](sync.md) - Full state synchronization
- [Public API](public.md) - Trending and discovery endpoints
