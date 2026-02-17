defmodule BaladosSyncCore.Dispatcher.Router do
  use Commanded.Commands.Router

  alias BaladosSyncCore.Aggregates.Subscription
  alias BaladosSyncCore.Aggregates.PlayTracking
  alias BaladosSyncCore.Aggregates.Playlist
  alias BaladosSyncCore.Aggregates.Collection
  alias BaladosSyncCore.Middleware.ValidateSubscription

  alias BaladosSyncCore.Commands.{
    Subscribe,
    Unsubscribe,
    RecordPlay,
    UpdatePosition,
    SaveEpisode,
    UnsaveEpisode,
    ShareEpisode,
    ChangePrivacy,
    RemoveEvents,
    SnapshotSubscription,
    SnapshotPlayTracking,
    SnapshotPlaylist,
    SnapshotCollection,
    CreatePlaylist,
    UpdatePlaylist,
    DeletePlaylist,
    ReorderPlaylist,
    ChangePlaylistVisibility,
    CreateCollection,
    AddFeedToCollection,
    RemoveFeedFromCollection,
    UpdateCollection,
    DeleteCollection,
    ReorderCollectionFeed,
    ChangeCollectionVisibility
  }

  # Registered globally (runs for all commands) because Commanded doesn't support
  # per-dispatch middleware. The passthrough clause is a no-op for non-AddFeedToCollection
  # commands, so the overhead is negligible.
  middleware(ValidateSubscription)

  # Each aggregate uses the same :user_id field for identity, so prefixes are
  # required to ensure each aggregate writes to its own event stream.
  # Without prefixes, Commanded would route all 4 aggregates to the same stream.

  # Subscription aggregate (subscriptions, privacy, sharing)
  identify(Subscription, by: :user_id, prefix: "subscription-")

  dispatch(
    [
      Subscribe,
      Unsubscribe,
      ShareEpisode,
      ChangePrivacy,
      RemoveEvents,
      SnapshotSubscription
    ],
    to: Subscription
  )

  # PlayTracking aggregate (play positions)
  identify(PlayTracking, by: :user_id, prefix: "play_tracking-")

  dispatch(
    [
      RecordPlay,
      UpdatePosition,
      SnapshotPlayTracking
    ],
    to: PlayTracking
  )

  # Playlist aggregate (playlists, episodes)
  identify(Playlist, by: :user_id, prefix: "playlist-")

  dispatch(
    [
      CreatePlaylist,
      UpdatePlaylist,
      DeletePlaylist,
      ReorderPlaylist,
      ChangePlaylistVisibility,
      SaveEpisode,
      UnsaveEpisode,
      SnapshotPlaylist
    ],
    to: Playlist
  )

  # Collection aggregate (feed organization)
  identify(Collection, by: :user_id, prefix: "collection-")

  dispatch(
    [
      CreateCollection,
      AddFeedToCollection,
      RemoveFeedFromCollection,
      UpdateCollection,
      DeleteCollection,
      ReorderCollectionFeed,
      ChangeCollectionVisibility,
      SnapshotCollection
    ],
    to: Collection
  )
end
