defmodule BaladosSyncCore.Aggregates.User do
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
    ShareEpisode,
    ChangePrivacy,
    RemoveEvents,
    SyncUserData,
    CreateCheckpoint
  }

  alias BaladosSyncCore.Events.{
    UserSubscribed,
    UserUnsubscribed,
    PlayRecorded,
    PositionUpdated,
    EpisodeSaved,
    EpisodeShared,
    PrivacyChanged,
    EventsRemoved,
    UserCheckpoint
  }

  # Initialisation de l'aggregate
  def execute(%__MODULE__{user_id: nil}, %Subscribe{} = cmd) do
    %UserSubscribed{
      user_id: cmd.user_id,
      device_id: cmd.device_id,
      device_name: cmd.device_name,
      rss_source_feed: cmd.rss_source_feed,
      rss_source_id: cmd.rss_source_id,
      subscribed_at: cmd.subscribed_at || DateTime.utc_now(),
      timestamp: DateTime.utc_now()
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
      event_infos: %{device_id: cmd.device_id, device_name: cmd.device_name}
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
      event_infos: %{device_id: cmd.device_id, device_name: cmd.device_name}
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
      event_infos: %{device_id: cmd.device_id, device_name: cmd.device_name}
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
      event_infos: %{device_id: cmd.device_id, device_name: cmd.device_name}
    }
  end

  # SaveEpisode
  def execute(%__MODULE__{} = user, %SaveEpisode{} = cmd) do
    %EpisodeSaved{
      user_id: user.user_id,
      rss_source_feed: cmd.rss_source_feed,
      rss_source_item: cmd.rss_source_item,
      timestamp: DateTime.utc_now(),
      event_infos: %{device_id: cmd.device_id, device_name: cmd.device_name}
    }
  end

  # ShareEpisode
  def execute(%__MODULE__{} = user, %ShareEpisode{} = cmd) do
    %EpisodeShared{
      user_id: user.user_id,
      rss_source_feed: cmd.rss_source_feed,
      rss_source_item: cmd.rss_source_item,
      timestamp: DateTime.utc_now(),
      event_infos: %{device_id: cmd.device_id, device_name: cmd.device_name}
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
      event_infos: %{device_id: cmd.device_id, device_name: cmd.device_name}
    }
  end

  # RemoveEvents
  def execute(%__MODULE__{} = user, %RemoveEvents{} = cmd) do
    %EventsRemoved{
      user_id: user.user_id,
      rss_source_feed: cmd.rss_source_feed,
      rss_source_item: cmd.rss_source_item,
      timestamp: DateTime.utc_now(),
      event_infos: %{device_id: cmd.device_id, device_name: cmd.device_name}
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

  # CreateCheckpoint
  def execute(%__MODULE__{} = user, %CreateCheckpoint{} = cmd) do
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
              event_infos: %{device_id: cmd.device_id, device_name: cmd.device_name}
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
                        event_infos: %{device_id: cmd.device_id, device_name: cmd.device_name}
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
                        event_infos: %{device_id: cmd.device_id, device_name: cmd.device_name}
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
                        event_infos: %{device_id: cmd.device_id, device_name: cmd.device_name}
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
                        event_infos: %{device_id: cmd.device_id, device_name: cmd.device_name}
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
              event_infos: %{device_id: cmd.device_id, device_name: cmd.device_name}
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
                event_infos: %{device_id: cmd.device_id, device_name: cmd.device_name}
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
