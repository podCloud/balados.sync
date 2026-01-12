# Extended OPML Format Specification

This document describes the Balados Sync extended OPML format. External applications can use this specification to generate OPML files compatible with Balados Sync import.

## Overview

The extended OPML format builds on standard OPML 2.0 with a custom namespace for additional data:
- Subscription metadata (dates, privacy)
- Play statuses (episode progress)
- Playlists and queues
- Collections

**Key principle**: The format is 100% backwards compatible with standard OPML readers. They will import subscriptions normally and ignore the Balados extensions.

## Namespace

```
xmlns:balados="https://balados.sync/opml/1.0"
```

## Document Structure

```xml
<?xml version="1.0" encoding="UTF-8"?>
<opml version="2.0" xmlns:balados="https://balados.sync/opml/1.0">
  <head>
    <title>Username - Balados Sync Export</title>
    <dateCreated>Sun, 12 Jan 2026 10:30:00 GMT</dateCreated>
    <balados:version>1.0</balados:version>
  </head>
  <body>
    <outline text="Subscriptions">
      <!-- Subscription outlines -->
    </outline>
    <outline text="Playlists" balados:type="playlists">
      <!-- Playlist outlines -->
    </outline>
    <outline text="Collections" balados:type="collections">
      <!-- Collection outlines -->
    </outline>
  </body>
</opml>
```

## Data Types

| Type | Format | Example |
|------|--------|---------|
| Date | RFC 822 | `Sun, 12 Jan 2026 10:30:00 GMT` |
| Boolean | `"true"` / `"false"` | `balados:played="true"` |
| Integer | Decimal string | `balados:position="1234"` |
| String | XML-escaped text | `balados:name="My &amp; Playlist"` |
| UUID | Standard UUID format | `balados:id="550e8400-e29b-41d4-a716-446655440000"` |

## Subscriptions Section

### Standard Attributes (OPML 2.0)

| Attribute | Required | Description |
|-----------|----------|-------------|
| `type` | Yes | Must be `"rss"` |
| `text` | Yes | Podcast title |
| `xmlUrl` | Yes | RSS feed URL |

### Balados Extensions

| Attribute | Required | Description |
|-----------|----------|-------------|
| `balados:subscribedAt` | No | When user subscribed (RFC 822) |
| `balados:unsubscribedAt` | No | When user unsubscribed (RFC 822) |
| `balados:privacy` | No | Privacy level: `"public"`, `"anonymous"`, or `"private"` (default: `"public"`) |
| `balados:sourceId` | No | Internal podcast identifier |

### Example

```xml
<outline text="Subscriptions">
  <outline type="rss"
           text="My Favorite Podcast"
           xmlUrl="https://example.com/feed.xml"
           balados:subscribedAt="Sun, 01 Dec 2025 08:00:00 GMT"
           balados:privacy="public"
           balados:sourceId="abc123">
    <!-- Play statuses nested here -->
  </outline>
</outline>
```

## Play Statuses

Play statuses are nested inside their parent subscription outline.

### Attributes

| Attribute | Required | Description |
|-----------|----------|-------------|
| `balados:type` | Yes | Must be `"playStatus"` |
| `balados:guid` | Yes | Episode GUID from RSS (see GUID handling below) |
| `balados:position` | Yes | Playback position in seconds |
| `balados:played` | Yes | Whether episode is marked as played |
| `balados:updatedAt` | No | Last update timestamp (RFC 822) |

### Example

```xml
<outline type="rss" text="Podcast Name" xmlUrl="https://example.com/feed.xml"
         balados:subscribedAt="Sun, 01 Dec 2025 08:00:00 GMT">
  <outline balados:type="playStatus"
           balados:guid="episode-unique-id-123"
           balados:position="1234"
           balados:played="false"
           balados:updatedAt="Sat, 11 Jan 2026 15:30:00 GMT"/>
  <outline balados:type="playStatus"
           balados:guid="episode-unique-id-456"
           balados:position="3600"
           balados:played="true"
           balados:updatedAt="Fri, 10 Jan 2026 20:00:00 GMT"/>
</outline>
```

## GUID Handling

### Standard GUIDs

Use the `<guid>` value from the RSS feed as-is:

```xml
balados:guid="https://example.com/episodes/123"
balados:guid="urn:uuid:550e8400-e29b-41d4-a716-446655440000"
balados:guid="episode-slug-name"
```

### Fallback for Missing GUIDs

When an RSS episode doesn't have a `<guid>` element, use the enclosure URL:

```xml
balados:guid="https://example.com/audio/episode.mp3"
```

### Generated GUIDs (Last Resort)

If neither GUID nor enclosure URL is available, generate a Balados fallback GUID:

```
balados:generated:{base64url(feed_url + ":" + enclosure_url)}
```

Example:
```xml
balados:guid="balados:generated:aHR0cHM6Ly9leGFtcGxlLmNvbS9mZWVkLnhtbDpodHRwczovL2V4YW1wbGUuY29tL2F1ZGlvLm1wMw"
```

## Playlists Section

The playlists section contains both regular playlists and device queues.

### Section Attributes

```xml
<outline text="Playlists" balados:type="playlists">
```

### Playlist Attributes

| Attribute | Required | Description |
|-----------|----------|-------------|
| `balados:type` | Yes | Must be `"playlist"` |
| `balados:id` | No | UUID for merge/update (generated if missing) |
| `balados:name` | Yes | Playlist name |
| `balados:description` | No | Playlist description |
| `balados:playlistType` | No | `"playlist"` (default) or `"queue"` |
| `balados:isPublic` | No | Whether publicly visible (default: `"false"`) |
| `balados:updatedAt` | No | Last update timestamp (RFC 822) |

### Playlist Item Attributes

| Attribute | Required | Description |
|-----------|----------|-------------|
| `balados:type` | Yes | Must be `"playlistItem"` |
| `balados:feedUrl` | Yes | RSS feed URL |
| `balados:guid` | Yes | Episode GUID |
| `balados:position` | Yes | Order in playlist (0-indexed) |
| `balados:itemTitle` | No | Episode title |
| `balados:feedTitle` | No | Podcast title |

### Example

```xml
<outline text="Playlists" balados:type="playlists">
  <outline balados:type="playlist"
           balados:id="550e8400-e29b-41d4-a716-446655440000"
           balados:name="Road Trip Mix"
           balados:description="Long episodes for driving"
           balados:playlistType="playlist"
           balados:isPublic="true"
           balados:updatedAt="Sat, 11 Jan 2026 12:00:00 GMT">
    <outline balados:type="playlistItem"
             balados:feedUrl="https://example.com/feed.xml"
             balados:guid="episode-123"
             balados:position="0"
             balados:itemTitle="Episode One"
             balados:feedTitle="Podcast Name"/>
    <outline balados:type="playlistItem"
             balados:feedUrl="https://other.com/feed.xml"
             balados:guid="ep-456"
             balados:position="1"/>
  </outline>

  <!-- Device queue example -->
  <outline balados:type="playlist"
           balados:id="device-queue-iphone"
           balados:name="Queue - iPhone"
           balados:playlistType="queue"
           balados:isPublic="false">
    <!-- items -->
  </outline>
</outline>
```

## Collections Section

Collections are groups of podcast subscriptions.

### Section Attributes

```xml
<outline text="Collections" balados:type="collections">
```

### Collection Attributes

| Attribute | Required | Description |
|-----------|----------|-------------|
| `balados:type` | Yes | Must be `"collection"` |
| `balados:id` | No | UUID for merge/update |
| `balados:title` | Yes | Collection title |
| `balados:description` | No | Collection description |
| `balados:isPublic` | No | Whether publicly visible (default: `"false"`) |
| `balados:color` | No | Theme color (hex format: `#RRGGBB`) |
| `balados:updatedAt` | No | Last update timestamp (RFC 822) |

### Collection Feed Attributes

| Attribute | Required | Description |
|-----------|----------|-------------|
| `balados:type` | Yes | Must be `"collectionFeed"` |
| `balados:feedUrl` | Yes | RSS feed URL |

### Example

```xml
<outline text="Collections" balados:type="collections">
  <outline balados:type="collection"
           balados:id="550e8400-e29b-41d4-a716-446655440001"
           balados:title="Tech Podcasts"
           balados:description="My favorite tech shows"
           balados:isPublic="false"
           balados:color="#3B82F6"
           balados:updatedAt="Fri, 10 Jan 2026 08:00:00 GMT">
    <outline balados:type="collectionFeed"
             balados:feedUrl="https://example.com/feed.xml"/>
    <outline balados:type="collectionFeed"
             balados:feedUrl="https://other.com/tech.xml"/>
  </outline>
</outline>
```

## Complete Example

```xml
<?xml version="1.0" encoding="UTF-8"?>
<opml version="2.0" xmlns:balados="https://balados.sync/opml/1.0">
  <head>
    <title>pof - Balados Sync Export</title>
    <dateCreated>Sun, 12 Jan 2026 10:30:00 GMT</dateCreated>
    <balados:version>1.0</balados:version>
  </head>
  <body>
    <outline text="Subscriptions">
      <outline type="rss"
               text="The Daily Tech"
               xmlUrl="https://dailytech.com/feed.xml"
               balados:subscribedAt="Mon, 15 Nov 2025 09:00:00 GMT"
               balados:privacy="public">
        <outline balados:type="playStatus"
                 balados:guid="dt-2026-01-11"
                 balados:position="1845"
                 balados:played="false"
                 balados:updatedAt="Sun, 12 Jan 2026 08:15:00 GMT"/>
      </outline>
      <outline type="rss"
               text="History Hour"
               xmlUrl="https://historyhour.net/rss"
               balados:subscribedAt="Wed, 01 Jan 2025 12:00:00 GMT"
               balados:privacy="anonymous"/>
    </outline>

    <outline text="Playlists" balados:type="playlists">
      <outline balados:type="playlist"
               balados:id="a1b2c3d4-e5f6-7890-abcd-ef1234567890"
               balados:name="Commute Playlist"
               balados:playlistType="playlist"
               balados:isPublic="false"
               balados:updatedAt="Sat, 11 Jan 2026 18:00:00 GMT">
        <outline balados:type="playlistItem"
                 balados:feedUrl="https://dailytech.com/feed.xml"
                 balados:guid="dt-2026-01-10"
                 balados:position="0"
                 balados:itemTitle="Friday Roundup"
                 balados:feedTitle="The Daily Tech"/>
      </outline>
    </outline>

    <outline text="Collections" balados:type="collections">
      <outline balados:type="collection"
               balados:id="c0ll3ct10n-1d00-0000-0000-000000000001"
               balados:title="News"
               balados:isPublic="false"
               balados:updatedAt="Thu, 09 Jan 2026 10:00:00 GMT">
        <outline balados:type="collectionFeed"
                 balados:feedUrl="https://dailytech.com/feed.xml"/>
      </outline>
    </outline>
  </body>
</opml>
```

## Import Behavior

### Conflict Resolution

When importing data that already exists:

| Data Type | Strategy |
|-----------|----------|
| Subscriptions | Last-Write-Wins based on `subscribedAt` |
| Play Statuses | Merge: highest position wins, played=true wins |
| Playlists | Last-Write-Wins based on `updatedAt`, items merged |
| Collections | Last-Write-Wins based on `updatedAt`, feeds merged |

### ID Handling

- If `balados:id` is provided, it's used for matching existing records
- If no ID is provided, matching is done by name/title
- New records get auto-generated UUIDs

### Deleted Data

Deleted items are **not** exported. Import only adds or updates data, never deletes.

## Standard OPML Compatibility

When importing a standard OPML file (without Balados namespace):

1. All `<outline type="rss">` elements are imported as subscriptions
2. `text` attribute becomes the podcast title
3. `xmlUrl` attribute becomes the feed URL
4. Default values: `privacy="public"`, `subscribedAt=now`
5. No play statuses, playlists, or collections are imported

This ensures any podcast app's OPML export will work with Balados Sync.

## Validation

External apps should validate their OPML output:

1. **XML well-formedness**: Valid XML with proper escaping
2. **Required attributes**: All "Required: Yes" attributes must be present
3. **Date format**: RFC 822 dates must be parseable
4. **URLs**: Feed URLs should be valid HTTP(S) URLs
5. **GUIDs**: Episode GUIDs should match RSS feed `<guid>` elements

## Version History

| Version | Date | Changes |
|---------|------|---------|
| 1.0 | 2026-01-12 | Initial release |
