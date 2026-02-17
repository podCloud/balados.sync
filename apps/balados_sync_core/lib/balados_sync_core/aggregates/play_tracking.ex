defmodule BaladosSyncCore.Aggregates.PlayTracking do
  @moduledoc """
  Play tracking aggregate for the CQRS/Event Sourcing system.

  Handles recording and updating play positions for podcast episodes.
  Split from the monolithic User aggregate as part of bounded context separation.

  ## State

  - `user_id` - Unique identifier for the user
  - `play_statuses` - Map of `%{rss_source_item => %{position, played, updated_at, rss_source_feed}}`
  """

  defstruct [
    :user_id,
    # %{rss_source_item => %{position, played, updated_at, rss_source_feed}}
    :play_statuses
  ]

  alias BaladosSyncCore.Commands.{RecordPlay, UpdatePosition}
  alias BaladosSyncCore.Events.{PlayRecorded, PositionUpdated}

  # Initialisation de l'aggregate (user_id nil = first command)
  def execute(%__MODULE__{user_id: nil}, %RecordPlay{} = cmd) do
    %PlayRecorded{
      user_id: cmd.user_id,
      rss_source_feed: cmd.rss_source_feed,
      rss_source_item: cmd.rss_source_item,
      position: cmd.position,
      played: cmd.played,
      timestamp: DateTime.utc_now(),
      event_infos: cmd.event_infos || %{}
    }
  end

  def execute(%__MODULE__{} = _state, %RecordPlay{} = cmd) do
    %PlayRecorded{
      user_id: cmd.user_id,
      rss_source_feed: cmd.rss_source_feed,
      rss_source_item: cmd.rss_source_item,
      position: cmd.position,
      played: cmd.played,
      timestamp: DateTime.utc_now(),
      event_infos: cmd.event_infos || %{}
    }
  end

  def execute(%__MODULE__{user_id: nil}, %UpdatePosition{} = cmd) do
    %PositionUpdated{
      user_id: cmd.user_id,
      rss_source_feed: cmd.rss_source_feed,
      rss_source_item: cmd.rss_source_item,
      position: cmd.position,
      timestamp: DateTime.utc_now(),
      event_infos: cmd.event_infos || %{}
    }
  end

  def execute(%__MODULE__{} = _state, %UpdatePosition{} = cmd) do
    %PositionUpdated{
      user_id: cmd.user_id,
      rss_source_feed: cmd.rss_source_feed,
      rss_source_item: cmd.rss_source_item,
      position: cmd.position,
      timestamp: DateTime.utc_now(),
      event_infos: cmd.event_infos || %{}
    }
  end

  # Apply events
  def apply(%__MODULE__{} = state, %PlayRecorded{} = event) do
    play_statuses = state.play_statuses || %{}

    status = %{
      position: event.position,
      played: event.played,
      updated_at: event.timestamp,
      rss_source_feed: event.rss_source_feed
    }

    %{state | user_id: event.user_id, play_statuses: Map.put(play_statuses, event.rss_source_item, status)}
  end

  def apply(%__MODULE__{} = state, %PositionUpdated{} = event) do
    play_statuses = state.play_statuses || %{}

    existing = Map.get(play_statuses, event.rss_source_item, %{})

    updated =
      Map.merge(existing, %{
        position: event.position,
        updated_at: event.timestamp,
        rss_source_feed: event.rss_source_feed
      })

    %{state | user_id: event.user_id, play_statuses: Map.put(play_statuses, event.rss_source_item, updated)}
  end

  def apply(%__MODULE__{} = state, _event), do: state
end
