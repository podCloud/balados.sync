defmodule BaladosSyncCore.Dispatcher.Router do
  use Commanded.Commands.Router

  alias BaladosSyncCore.Aggregates.User
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
    SyncUserData,
    Snapshot,
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

  # User aggregate (subscriptions, privacy)
  identify(User, by: :user_id)

  dispatch(
    [
      Subscribe,
      Unsubscribe,
      ShareEpisode,
      ChangePrivacy,
      RemoveEvents,
      SyncUserData,
      Snapshot
    ],
    to: User
  )

  # PlayTracking aggregate (play positions)
  identify(PlayTracking, by: :user_id)

  dispatch(
    [
      RecordPlay,
      UpdatePosition
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
      UnsaveEpisode
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
      ChangeCollectionVisibility
    ],
    to: Collection
  )
end
