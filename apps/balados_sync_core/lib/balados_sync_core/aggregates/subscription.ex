defmodule BaladosSyncCore.Aggregates.Subscription do
  @moduledoc """
  Subscription aggregate for the CQRS/Event Sourcing system.

  Handles user subscriptions, privacy settings, and cross-cutting concerns
  (episode sharing, event removal).

  ## Bounded Context

  This aggregate is part of the subscription bounded context. Other domains
  are handled by dedicated aggregates:
  - `PlayTracking` - play positions
  - `Playlist` - playlists and episodes
  - `Collection` - feed organization

  ## State

  - `user_id` - Unique identifier for the user
  - `privacy` - Privacy level: `:public`, `:anonymous`, or `:private`
  - `subscriptions` - Map of `%{feed => %{subscribed_at, unsubscribed_at, rss_source_id}}`
  """

  defstruct [
    :user_id,
    # :public | :anonymous | :private
    :privacy,
    # %{rss_source_feed => %{subscribed_at, unsubscribed_at}}
    :subscriptions
  ]

  alias BaladosSyncCore.Commands.{
    Subscribe,
    Unsubscribe,
    ShareEpisode,
    ChangePrivacy,
    RemoveEvents,
    SnapshotSubscription
  }

  alias BaladosSyncCore.Events.{
    UserSubscribed,
    UserUnsubscribed,
    EpisodeShared,
    PrivacyChanged,
    EventsRemoved,
    SubscriptionCheckpoint
  }

  # Subscribe
  def execute(%__MODULE__{}, %Subscribe{} = cmd) do
    %UserSubscribed{
      user_id: cmd.user_id,
      rss_source_feed: cmd.rss_source_feed,
      rss_source_id: cmd.rss_source_id,
      subscribed_at: cmd.subscribed_at || DateTime.utc_now() |> DateTime.truncate(:second),
      timestamp: DateTime.utc_now() |> DateTime.truncate(:second),
      event_infos: cmd.event_infos || %{}
    }
  end

  # Unsubscribe
  def execute(%__MODULE__{}, %Unsubscribe{} = cmd) do
    %UserUnsubscribed{
      user_id: cmd.user_id,
      rss_source_feed: cmd.rss_source_feed,
      rss_source_id: cmd.rss_source_id,
      unsubscribed_at: cmd.unsubscribed_at || DateTime.utc_now() |> DateTime.truncate(:second),
      timestamp: DateTime.utc_now() |> DateTime.truncate(:second),
      event_infos: cmd.event_infos || %{}
    }
  end

  # ShareEpisode
  def execute(%__MODULE__{}, %ShareEpisode{} = cmd) do
    %EpisodeShared{
      user_id: cmd.user_id,
      rss_source_feed: cmd.rss_source_feed,
      rss_source_item: cmd.rss_source_item,
      timestamp: DateTime.utc_now() |> DateTime.truncate(:second),
      event_infos: cmd.event_infos || %{}
    }
  end

  # ChangePrivacy
  # Note: rss_source_feed and rss_source_item fields are carried through from the
  # command for event metadata/audit purposes, but are not used by the aggregate's
  # apply/2 (which only updates state.privacy). They may be used by projectors.
  def execute(%__MODULE__{}, %ChangePrivacy{} = cmd) do
    %PrivacyChanged{
      user_id: cmd.user_id,
      rss_source_feed: cmd.rss_source_feed,
      rss_source_item: cmd.rss_source_item,
      privacy: cmd.privacy,
      timestamp: DateTime.utc_now() |> DateTime.truncate(:second),
      event_infos: cmd.event_infos || %{}
    }
  end

  # RemoveEvents
  def execute(%__MODULE__{}, %RemoveEvents{} = cmd) do
    %EventsRemoved{
      user_id: cmd.user_id,
      rss_source_feed: cmd.rss_source_feed,
      rss_source_item: cmd.rss_source_item,
      timestamp: DateTime.utc_now() |> DateTime.truncate(:second),
      event_infos: cmd.event_infos || %{}
    }
  end

  # SnapshotSubscription
  def execute(%__MODULE__{} = state, %SnapshotSubscription{} = _cmd) do
    %SubscriptionCheckpoint{
      user_id: state.user_id,
      subscriptions: filter_subscriptions(state.subscriptions || %{}),
      privacy: state.privacy,
      timestamp: DateTime.utc_now() |> DateTime.truncate(:second)
    }
  end

  # Apply events
  def apply(%__MODULE__{} = state, %UserSubscribed{} = event) do
    subscriptions = state.subscriptions || %{}

    updated_sub = %{
      subscribed_at: event.subscribed_at,
      unsubscribed_at: nil,
      rss_source_id: event.rss_source_id
    }

    %{
      state
      | user_id: event.user_id,
        subscriptions: Map.put(subscriptions, event.rss_source_feed, updated_sub)
    }
  end

  def apply(%__MODULE__{} = state, %UserUnsubscribed{} = event) do
    subscriptions = state.subscriptions || %{}

    case Map.get(subscriptions, event.rss_source_feed) do
      nil ->
        state

      sub ->
        updated_sub = Map.put(sub, :unsubscribed_at, event.unsubscribed_at)
        %{state | subscriptions: Map.put(subscriptions, event.rss_source_feed, updated_sub)}
    end
  end

  def apply(%__MODULE__{} = state, %PrivacyChanged{} = event) do
    %{state | privacy: event.privacy}
  end

  def apply(%__MODULE__{} = state, %SubscriptionCheckpoint{} = event) do
    %{state | user_id: event.user_id, subscriptions: event.subscriptions, privacy: event.privacy || :public}
  end

  def apply(%__MODULE__{} = state, _event), do: state

  # Filters out subscriptions that were unsubscribed more than 45 days ago.
  # Active subscriptions and recent unsubscriptions are preserved.
  # The unsubscribed_at > subscribed_at guard prevents filtering entries with
  # corrupted timestamps (e.g. unsubscribed before subscribed).
  defp filter_subscriptions(subscriptions) do
    forty_five_days_ago = DateTime.add(DateTime.utc_now(), -45, :day)

    subscriptions
    |> Enum.reject(fn {_feed, sub} ->
      sub.unsubscribed_at != nil &&
        DateTime.compare(sub.unsubscribed_at, sub.subscribed_at || DateTime.from_unix!(0)) == :gt &&
        DateTime.compare(sub.unsubscribed_at, forty_five_days_ago) == :lt
    end)
    |> Enum.into(%{})
  end
end
