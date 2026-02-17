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

  middleware(ValidateSubscription)

  # Subscription aggregate (subscriptions, privacy, sharing)
  identify(Subscription, by: :user_id)

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
  identify(PlayTracking, by: :user_id)

  dispatch(
    [
      RecordPlay,
      UpdatePosition,
      SnapshotPlayTracking
    ],
    to: PlayTracking
  )

  # Playlist aggregate (playlists, episodes)
  identify(Playlist, by: :user_id)

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
  identify(Collection, by: :user_id)

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
