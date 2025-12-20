defmodule BaladosSyncCore.Dispatcher.Router do
  use Commanded.Commands.Router

  alias BaladosSyncCore.Aggregates.User

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

  # Toutes les commandes sont routées vers l'aggregate User
  # identifié par user_id
  identify(User, by: :user_id)

  dispatch(
    [
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
    ],
    to: User
  )
end
