defmodule BaladosSyncCore.Aggregates.User do
  @moduledoc """
  User aggregate for the CQRS/Event Sourcing system.

  After bounded context separation, this aggregate handles only subscriptions,
  privacy, and cross-cutting concerns (share, remove events, sync, snapshot).

  Other domains are handled by dedicated aggregates:
  - `PlayTracking` - play positions
  - `Playlist` - playlists and episodes
  - `Collection` - feed organization

  ## State

  - `user_id` - Unique identifier for the user
  - `privacy` - Privacy level: `:public`, `:anonymous`, or `:private`
  - `subscriptions` - Map of `%{feed => %{subscribed_at, unsubscribed_at, rss_source_id}}`
  - `play_statuses` - Kept for snapshot/checkpoint backward compatibility
  - `playlists` - Kept for snapshot/checkpoint backward compatibility
  - `collections` - Kept for snapshot/checkpoint backward compatibility
  """

  defstruct [
    :user_id,
    # :public | :anonymous | :private
    :privacy,
    # %{rss_source_feed => %{subscribed_at, unsubscribed_at}}
    :subscriptions,
    # Kept for snapshot backward compat (will be removed in Phase 5)
    :play_statuses,
    :playlists,
    :collections
  ]

  alias BaladosSyncCore.Commands.{
    Subscribe,
    Unsubscribe,
    ShareEpisode,
    ChangePrivacy,
    RemoveEvents,
    SyncUserData,
    Snapshot
  }

  alias BaladosSyncCore.Events.{
    UserSubscribed,
    UserUnsubscribed,
    EpisodeShared,
    PrivacyChanged,
    EventsRemoved,
    UserCheckpoint
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

  # SyncUserData - No-op at aggregate level
  def execute(%__MODULE__{} = _user, %SyncUserData{} = _cmd) do
    []
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
  defp filter_subscriptions(subscriptions) do
    now = DateTime.utc_now()
    forty_five_days_ago = DateTime.add(now, -45, :day)

    subscriptions
    |> Enum.filter(fn {_feed, sub} ->
      cond do
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
