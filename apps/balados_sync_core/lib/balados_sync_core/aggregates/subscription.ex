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
    RemoveEvents
  }

  alias BaladosSyncCore.Events.{
    UserSubscribed,
    UserUnsubscribed,
    EpisodeShared,
    PrivacyChanged,
    EventsRemoved
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
  def execute(%__MODULE__{} = state, %Subscribe{} = cmd) do
    %UserSubscribed{
      user_id: state.user_id,
      rss_source_feed: cmd.rss_source_feed,
      rss_source_id: cmd.rss_source_id,
      subscribed_at: cmd.subscribed_at || DateTime.utc_now(),
      timestamp: DateTime.utc_now(),
      event_infos: cmd.event_infos || %{}
    }
  end

  # Unsubscribe
  def execute(%__MODULE__{} = state, %Unsubscribe{} = cmd) do
    %UserUnsubscribed{
      user_id: state.user_id,
      rss_source_feed: cmd.rss_source_feed,
      rss_source_id: cmd.rss_source_id,
      unsubscribed_at: cmd.unsubscribed_at || DateTime.utc_now(),
      timestamp: DateTime.utc_now(),
      event_infos: cmd.event_infos || %{}
    }
  end

  # ShareEpisode
  def execute(%__MODULE__{} = state, %ShareEpisode{} = cmd) do
    %EpisodeShared{
      user_id: state.user_id,
      rss_source_feed: cmd.rss_source_feed,
      rss_source_item: cmd.rss_source_item,
      timestamp: DateTime.utc_now(),
      event_infos: cmd.event_infos || %{}
    }
  end

  # ChangePrivacy
  def execute(%__MODULE__{} = state, %ChangePrivacy{} = cmd) do
    %PrivacyChanged{
      user_id: state.user_id,
      rss_source_feed: cmd.rss_source_feed,
      rss_source_item: cmd.rss_source_item,
      privacy: cmd.privacy,
      timestamp: DateTime.utc_now(),
      event_infos: cmd.event_infos || %{}
    }
  end

  # RemoveEvents
  def execute(%__MODULE__{} = state, %RemoveEvents{} = cmd) do
    %EventsRemoved{
      user_id: state.user_id,
      rss_source_feed: cmd.rss_source_feed,
      rss_source_item: cmd.rss_source_item,
      timestamp: DateTime.utc_now(),
      event_infos: cmd.event_infos || %{}
    }
  end

  # Application des events pour mettre à jour l'état
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

  def apply(%__MODULE__{} = state, _event), do: state

  # Public helper for snapshot worker
  def filter_subscriptions(subscriptions) do
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
