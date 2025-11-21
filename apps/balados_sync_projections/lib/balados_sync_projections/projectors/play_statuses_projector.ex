defmodule BaladosSyncProjections.Projectors.PlayStatusesProjector do
  use Commanded.Projections.Ecto,
    application: BaladosSyncCore.App,
    repo: BaladosSyncProjections.Repo,
    name: "PlayStatusesProjector"

  alias BaladosSyncCore.Events.{PlayRecorded, PositionUpdated, UserCheckpoint}
  alias BaladosSyncProjections.Schemas.PlayStatus

  project(%PlayRecorded{} = event, _metadata, fn multi ->
    Ecto.Multi.insert(
      multi,
      :play_status,
      %PlayStatus{
        user_id: event.user_id,
        rss_source_feed: event.rss_source_feed,
        rss_source_item: event.rss_source_item,
        position: event.position,
        played: event.played,
        updated_at: event.timestamp
      },
      on_conflict: {:replace, [:position, :played, :updated_at, :rss_source_feed]},
      conflict_target: [:user_id, :rss_source_item]
    )
  end)

  project(%PositionUpdated{} = event, _metadata, fn multi ->
    Ecto.Multi.insert(
      multi,
      :play_status,
      %PlayStatus{
        user_id: event.user_id,
        rss_source_feed: event.rss_source_feed,
        rss_source_item: event.rss_source_item,
        position: event.position,
        updated_at: event.timestamp
      },
      on_conflict: [
        set: [
          position: event.position,
          updated_at: event.timestamp,
          rss_source_feed: event.rss_source_feed
        ]
      ],
      conflict_target: [:user_id, :rss_source_item]
    )
  end)

  project(%UserCheckpoint{} = event, _metadata, fn multi ->
    Enum.reduce(event.play_statuses, multi, fn {item, status}, acc ->
      Ecto.Multi.insert(
        acc,
        {:play_status, item},
        %PlayStatus{
          user_id: event.user_id,
          rss_source_feed: status.rss_source_feed,
          rss_source_item: item,
          position: status.position,
          played: status.played,
          updated_at: status.updated_at
        },
        on_conflict: {:replace_all_except, [:id]},
        conflict_target: [:user_id, :rss_source_item]
      )
    end)
  end)
end
