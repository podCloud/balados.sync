defmodule BaladosSyncCore.Aggregates.User do
  @moduledoc """
  User aggregate for the CQRS/Event Sourcing system.

  This aggregate is the core of the Balados Sync domain model. It encapsulates all
  business logic for managing user subscriptions, play statuses, playlists, and privacy
  settings. The aggregate follows the CQRS/ES pattern with two key functions:

  ## CQRS/ES Pattern

  - `execute/2` - Validates commands and returns events (command → event)
  - `apply/2` - Updates aggregate state based on events (event → state)

  ## State Management

  The aggregate state is rebuilt by replaying all events for a user from the event store.
  State is never persisted directly - it's always derived from the event stream.

  ### Aggregate State Structure

  - `user_id` - Unique identifier for the user
  - `privacy` - Privacy level: `:public`, `:anonymous`, or `:private`
  - `subscriptions` - Map of `%{feed => %{subscribed_at, unsubscribed_at, rss_source_id}}`
  - `play_statuses` - Map of `%{item => %{position, played, updated_at, rss_source_feed}}`
  - `playlists` - Map of `%{playlist_id => %{name, items}}` (TODO)

  ## Command Flow

  1. Command arrives via Dispatcher (e.g., `Subscribe`)
  2. Dispatcher loads aggregate by rebuilding state from events
  3. `execute/2` validates command and returns event(s)
  4. EventStore persists events immutably
  5. `apply/2` updates aggregate state (for in-memory state)
  6. Projectors listen to events and update read models

  ## Event Sourcing Benefits

  - Complete audit trail of all user actions
  - Time travel: rebuild state at any point in history
  - Event replay for bug fixes or new projections
  - Natural support for sync conflicts (timestamp-based resolution)

  ## Aggregate Lifecycle

  The aggregate is stateless between command dispatches. Each command:
  1. Loads current state by replaying events
  2. Executes command logic
  3. Returns events to be persisted
  4. State updates happen via `apply/2` during replay

  ## Examples

      # Dispatch a command (through Dispatcher)
      Dispatcher.dispatch(%Subscribe{
        user_id: "user-123",
        rss_source_feed: "base64-feed",
        rss_source_id: "podcast-id"
      })

      # This internally:
      # 1. Loads User aggregate for "user-123"
      # 2. Calls execute(%User{}, %Subscribe{})
      # 3. Returns %UserSubscribed{} event
      # 4. Persists event to EventStore
      # 5. Calls apply(%User{}, %UserSubscribed{})
      # 6. Projectors update read models
  """

  defstruct [
    :user_id,
    # :public | :anonymous | :private
    :privacy,
    # %{rss_source_feed => %{subscribed_at, unsubscribed_at}}
    :subscriptions,
    # %{rss_source_item => %{position, played, updated_at}}
    :play_statuses,
    # %{playlist_id => %{name, items}}
    :playlists
  ]

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
    UpdatePlaylist,
    ReorderPlaylist
  }

  alias BaladosSyncCore.Events.{
    UserSubscribed,
    UserUnsubscribed,
    PlayRecorded,
    PositionUpdated,
    EpisodeSaved,
    EpisodeUnsaved,
    EpisodeShared,
    PrivacyChanged,
    EventsRemoved,
    UserCheckpoint,
    PlaylistUpdated,
    PlaylistReordered
  }

  # Initialisation de l'aggregate
  def execute(%__MODULE__{user_id: nil}, %Subscribe{} = cmd) do
    %UserSubscribed{
      user_id: cmd.user_id,
      rss_source_feed: cmd.rss_source_feed,
      rss_source_id: cmd.rss_source_id,
      subscribed_at: cmd.subscribed_at || DateTime.utc_now(),
      timestamp: DateTime.utc_now(),
      event_infos: cmd.event_infos || %{}
    }
  end

  # Subscribe
  def execute(%__MODULE__{} = user, %Subscribe{} = cmd) do
    %UserSubscribed{
      user_id: user.user_id,
      rss_source_feed: cmd.rss_source_feed,
      rss_source_id: cmd.rss_source_id,
      subscribed_at: cmd.subscribed_at || DateTime.utc_now(),
      timestamp: DateTime.utc_now(),
      event_infos: cmd.event_infos || %{}
    }
  end

  # Unsubscribe
  def execute(%__MODULE__{} = user, %Unsubscribe{} = cmd) do
    %UserUnsubscribed{
      user_id: user.user_id,
      rss_source_feed: cmd.rss_source_feed,
      rss_source_id: cmd.rss_source_id,
      unsubscribed_at: cmd.unsubscribed_at || DateTime.utc_now(),
      timestamp: DateTime.utc_now(),
      event_infos: cmd.event_infos || %{}
    }
  end

  # RecordPlay
  def execute(%__MODULE__{} = user, %RecordPlay{} = cmd) do
    %PlayRecorded{
      user_id: user.user_id,
      rss_source_feed: cmd.rss_source_feed,
      rss_source_item: cmd.rss_source_item,
      position: cmd.position,
      played: cmd.played,
      timestamp: DateTime.utc_now(),
      event_infos: cmd.event_infos || %{}
    }
  end

  # UpdatePosition
  def execute(%__MODULE__{} = user, %UpdatePosition{} = cmd) do
    %PositionUpdated{
      user_id: user.user_id,
      rss_source_feed: cmd.rss_source_feed,
      rss_source_item: cmd.rss_source_item,
      position: cmd.position,
      timestamp: DateTime.utc_now(),
      event_infos: cmd.event_infos || %{}
    }
  end

  # SaveEpisode
  def execute(%__MODULE__{} = user, %SaveEpisode{} = cmd) do
    %EpisodeSaved{
      user_id: user.user_id,
      playlist: cmd.playlist,
      rss_source_feed: cmd.rss_source_feed,
      rss_source_item: cmd.rss_source_item,
      item_title: cmd.item_title,
      feed_title: cmd.feed_title,
      timestamp: DateTime.utc_now(),
      event_infos: cmd.event_infos || %{}
    }
  end

  # UnsaveEpisode
  def execute(%__MODULE__{} = user, %UnsaveEpisode{} = cmd) do
    %EpisodeUnsaved{
      user_id: user.user_id,
      playlist: cmd.playlist,
      rss_source_feed: cmd.rss_source_feed,
      rss_source_item: cmd.rss_source_item,
      timestamp: DateTime.utc_now(),
      event_infos: cmd.event_infos || %{}
    }
  end

  # UpdatePlaylist
  def execute(%__MODULE__{} = user, %UpdatePlaylist{} = cmd) do
    %PlaylistUpdated{
      user_id: user.user_id,
      playlist: cmd.playlist,
      name: cmd.name,
      description: cmd.description,
      timestamp: DateTime.utc_now(),
      event_infos: cmd.event_infos || %{}
    }
  end

  # ReorderPlaylist
  def execute(%__MODULE__{} = user, %ReorderPlaylist{} = cmd) do
    %PlaylistReordered{
      user_id: user.user_id,
      playlist: cmd.playlist,
      items: cmd.items,
      timestamp: DateTime.utc_now(),
      event_infos: cmd.event_infos || %{}
    }
  end

  # ShareEpisode
  def execute(%__MODULE__{} = user, %ShareEpisode{} = cmd) do
    %EpisodeShared{
      user_id: user.user_id,
      rss_source_feed: cmd.rss_source_feed,
      rss_source_item: cmd.rss_source_item,
      timestamp: DateTime.utc_now(),
      event_infos: cmd.event_infos || %{}
    }
  end

  # ChangePrivacy
  def execute(%__MODULE__{} = user, %ChangePrivacy{} = cmd) do
    %PrivacyChanged{
      user_id: user.user_id,
      rss_source_feed: cmd.rss_source_feed,
      rss_source_item: cmd.rss_source_item,
      privacy: cmd.privacy,
      timestamp: DateTime.utc_now(),
      event_infos: cmd.event_infos || %{}
    }
  end

  # RemoveEvents
  def execute(%__MODULE__{} = user, %RemoveEvents{} = cmd) do
    %EventsRemoved{
      user_id: user.user_id,
      rss_source_feed: cmd.rss_source_feed,
      rss_source_item: cmd.rss_source_item,
      timestamp: DateTime.utc_now(),
      event_infos: cmd.event_infos || %{}
    }
  end

  # SyncUserData - Génère plusieurs events selon les diffs
  def execute(%__MODULE__{} = user, %SyncUserData{} = cmd) do
    events = []

    # Sync des subscriptions
    events = events ++ sync_subscriptions(user, cmd.subscriptions, cmd)

    # Sync des play_statuses
    events = events ++ sync_play_statuses(user, cmd.play_statuses, cmd)

    # TODO: Sync des playlists quand implémenté

    events
  end

  # Snapshot
  def execute(%__MODULE__{} = user, %Snapshot{} = _cmd) do
    %UserCheckpoint{
      user_id: user.user_id,
      subscriptions: filter_subscriptions(user.subscriptions),
      play_statuses: user.play_statuses,
      playlists: user.playlists,
      timestamp: DateTime.utc_now()
    }
  end

  # Application des events pour mettre à jour l'état
  def apply(%__MODULE__{} = user, %UserSubscribed{} = event) do
    subscriptions = user.subscriptions || %{}

    updated_sub = %{
      subscribed_at: event.subscribed_at,
      unsubscribed_at: nil,
      rss_source_id: event.rss_source_id
    }

    %{
      user
      | user_id: event.user_id,
        subscriptions: Map.put(subscriptions, event.rss_source_feed, updated_sub)
    }
  end

  def apply(%__MODULE__{} = user, %UserUnsubscribed{} = event) do
    subscriptions = user.subscriptions || %{}

    case Map.get(subscriptions, event.rss_source_feed) do
      nil ->
        user

      sub ->
        updated_sub = Map.put(sub, :unsubscribed_at, event.unsubscribed_at)
        %{user | subscriptions: Map.put(subscriptions, event.rss_source_feed, updated_sub)}
    end
  end

  def apply(%__MODULE__{} = user, %PlayRecorded{} = event) do
    play_statuses = user.play_statuses || %{}

    status = %{
      position: event.position,
      played: event.played,
      updated_at: event.timestamp,
      rss_source_feed: event.rss_source_feed
    }

    %{user | play_statuses: Map.put(play_statuses, event.rss_source_item, status)}
  end

  def apply(%__MODULE__{} = user, %PositionUpdated{} = event) do
    play_statuses = user.play_statuses || %{}

    existing = Map.get(play_statuses, event.rss_source_item, %{})

    updated =
      Map.merge(existing, %{
        position: event.position,
        updated_at: event.timestamp,
        rss_source_feed: event.rss_source_feed
      })

    %{user | play_statuses: Map.put(play_statuses, event.rss_source_item, updated)}
  end

  def apply(%__MODULE__{} = user, %PrivacyChanged{} = event) do
    %{user | privacy: event.privacy}
  end

  def apply(%__MODULE__{} = user, %EpisodeSaved{} = event) do
    playlists = user.playlists || %{}

    # Get or create playlist
    playlist = Map.get(playlists, event.playlist, %{
      name: event.playlist,
      items: []
    })

    # Add item to playlist if not already present
    items = playlist.items || []
    new_item = {event.rss_source_feed, event.rss_source_item}

    items = if Enum.any?(items, fn {feed, item} ->
      feed == event.rss_source_feed and item == event.rss_source_item
    end) do
      items
    else
      items ++ [new_item]
    end

    updated_playlist = %{playlist | items: items}
    %{user | playlists: Map.put(playlists, event.playlist, updated_playlist)}
  end

  def apply(%__MODULE__{} = user, %EpisodeUnsaved{} = event) do
    playlists = user.playlists || %{}

    case Map.get(playlists, event.playlist) do
      nil ->
        user

      playlist ->
        # Remove item from playlist
        items = playlist.items || []
        new_items = Enum.filter(items, fn {feed, item} ->
          not (feed == event.rss_source_feed and item == event.rss_source_item)
        end)

        updated_playlist = %{playlist | items: new_items}
        %{user | playlists: Map.put(playlists, event.playlist, updated_playlist)}
    end
  end

  def apply(%__MODULE__{} = user, %PlaylistUpdated{} = event) do
    playlists = user.playlists || %{}

    case Map.get(playlists, event.playlist) do
      nil ->
        user

      playlist ->
        updated_playlist = playlist
        updated_playlist = if event.name, do: %{updated_playlist | name: event.name}, else: updated_playlist
        updated_playlist = if event.description, do: %{updated_playlist | description: event.description}, else: updated_playlist
        %{user | playlists: Map.put(playlists, event.playlist, updated_playlist)}
    end
  end

  def apply(%__MODULE__{} = user, %PlaylistReordered{} = event) do
    playlists = user.playlists || %{}

    case Map.get(playlists, event.playlist) do
      nil ->
        user

      playlist ->
        # Reorder items based on the event's items list
        updated_playlist = %{playlist | items: event.items}
        %{user | playlists: Map.put(playlists, event.playlist, updated_playlist)}
    end
  end

  def apply(%__MODULE__{} = user, %UserCheckpoint{} = event) do
    %{
      user
      | subscriptions: event.subscriptions,
        play_statuses: event.play_statuses,
        playlists: event.playlists
    }
  end

  def apply(%__MODULE__{} = user, _event), do: user

  # Helpers privés
  defp sync_subscriptions(user, synced_subs, cmd) do
    current_subs = user.subscriptions || %{}

    Enum.flat_map(synced_subs, fn {feed, synced_sub} ->
      case Map.get(current_subs, feed) do
        nil ->
          # Subscription inconnue, on émet subscribe
          [
            %UserSubscribed{
              user_id: user.user_id,
              rss_source_feed: feed,
              rss_source_id: synced_sub.rss_source_id,
              subscribed_at: synced_sub.subscribed_at,
              timestamp: DateTime.utc_now(),
              event_infos: cmd.event_infos || %{}
            }
          ]

        server_sub ->
          cond do
            # Synced est subscribed
            is_subscribed?(synced_sub) ->
              cond do
                is_subscribed?(server_sub) ->
                  # Les deux subscribed, on prend le plus récent
                  if DateTime.compare(synced_sub.subscribed_at, server_sub.subscribed_at) == :gt do
                    [
                      %UserSubscribed{
                        user_id: user.user_id,
                        rss_source_feed: feed,
                        rss_source_id: synced_sub.rss_source_id,
                        subscribed_at: synced_sub.subscribed_at,
                        timestamp: DateTime.utc_now(),
                        event_infos: cmd.event_infos || %{}
                      }
                    ]
                  else
                    []
                  end

                true ->
                  # Server unsubscribed, synced subscribed
                  unsub_at = server_sub.unsubscribed_at || DateTime.from_unix!(0)

                  if DateTime.compare(synced_sub.subscribed_at, unsub_at) == :gt do
                    [
                      %UserSubscribed{
                        user_id: user.user_id,
                        rss_source_feed: feed,
                        rss_source_id: synced_sub.rss_source_id,
                        subscribed_at: synced_sub.subscribed_at,
                        timestamp: DateTime.utc_now(),
                        event_infos: cmd.event_infos || %{}
                      }
                    ]
                  else
                    []
                  end
              end

            # Synced est unsubscribed
            true ->
              cond do
                is_subscribed?(server_sub) ->
                  # Server subscribed, synced unsubscribed
                  if DateTime.compare(synced_sub.unsubscribed_at, server_sub.subscribed_at) == :gt do
                    [
                      %UserUnsubscribed{
                        user_id: user.user_id,
                        rss_source_feed: feed,
                        rss_source_id: synced_sub.rss_source_id,
                        unsubscribed_at: synced_sub.unsubscribed_at,
                        timestamp: DateTime.utc_now(),
                        event_infos: cmd.event_infos || %{}
                      }
                    ]
                  else
                    []
                  end

                true ->
                  # Les deux unsubscribed, on prend le plus récent
                  server_unsub = server_sub.unsubscribed_at || DateTime.from_unix!(0)

                  if DateTime.compare(synced_sub.unsubscribed_at, server_unsub) == :gt do
                    [
                      %UserUnsubscribed{
                        user_id: user.user_id,
                        rss_source_feed: feed,
                        rss_source_id: synced_sub.rss_source_id,
                        unsubscribed_at: synced_sub.unsubscribed_at,
                        timestamp: DateTime.utc_now(),
                        event_infos: cmd.event_infos || %{}
                      }
                    ]
                  else
                    []
                  end
              end
          end
      end
    end)
  end

  defp sync_play_statuses(user, synced_statuses, cmd) do
    current_statuses = user.play_statuses || %{}

    Enum.flat_map(synced_statuses, fn {item, synced_status} ->
      case Map.get(current_statuses, item) do
        nil ->
          # Nouveau play status
          [
            %PlayRecorded{
              user_id: user.user_id,
              rss_source_feed: synced_status.rss_source_feed,
              rss_source_item: item,
              position: synced_status.position,
              played: synced_status.played,
              timestamp: DateTime.utc_now(),
              event_infos: cmd.event_infos || %{}
            }
          ]

        server_status ->
          # On prend celui avec updated_at le plus récent
          if DateTime.compare(synced_status.updated_at, server_status.updated_at) == :gt do
            [
              %PlayRecorded{
                user_id: user.user_id,
                rss_source_feed: synced_status.rss_source_feed,
                rss_source_item: item,
                position: synced_status.position,
                played: synced_status.played,
                timestamp: DateTime.utc_now(),
                event_infos: cmd.event_infos || %{}
              }
            ]
          else
            []
          end
      end
    end)
  end

  defp is_subscribed?(sub) do
    sub_at = sub.subscribed_at || DateTime.from_unix!(0)
    unsub_at = sub.unsubscribed_at || DateTime.from_unix!(0)
    DateTime.compare(sub_at, unsub_at) == :gt
  end

  defp filter_subscriptions(subscriptions) do
    now = DateTime.utc_now()
    forty_five_days_ago = DateTime.add(now, -45, :day)

    subscriptions
    |> Enum.filter(fn {_feed, sub} ->
      cond do
        # Si unsubscribed > 45j, on ne garde pas
        sub.unsubscribed_at &&
          DateTime.compare(sub.unsubscribed_at, forty_five_days_ago) == :lt &&
            DateTime.compare(sub.unsubscribed_at, sub.subscribed_at || DateTime.from_unix!(0)) ==
              :gt ->
          false

        true ->
          true
      end
    end)
    |> Enum.into(%{})
  end
end
