defmodule BaladosSyncProjections.Projectors.SubscriptionsProjector do
  use Commanded.Projections.Ecto,
    application: BaladosSyncCore.Dispatcher,
    repo: BaladosSyncProjections.ProjectionsRepo,
    name: "SubscriptionsProjector"

  require Logger
  import Ecto.Query

  alias BaladosSyncCore.Events.{UserSubscribed, UserUnsubscribed, UserCheckpoint, SubscriptionCheckpoint}
  alias BaladosSyncProjections.Schemas.Subscription

  project(%UserSubscribed{} = event, _metadata, fn multi ->
    # Insérer la subscription immédiatement (ne pas bloquer sur fetch RSS)
    subscribed_at = parse_datetime(event.subscribed_at)

    Ecto.Multi.insert(
      multi,
      :subscription,
      %Subscription{
        user_id: event.user_id,
        rss_source_feed: event.rss_source_feed,
        rss_source_id: event.rss_source_id,
        subscribed_at: subscribed_at,
        unsubscribed_at: nil
      },
      on_conflict: {:replace, [:subscribed_at, :unsubscribed_at, :rss_source_id, :updated_at]},
      conflict_target: [:user_id, :rss_source_feed]
    )
  end)

  project(%UserUnsubscribed{} = event, _metadata, fn multi ->
    Ecto.Multi.update_all(
      multi,
      :subscription,
      from(s in Subscription,
        where: s.user_id == ^event.user_id and s.rss_source_feed == ^event.rss_source_feed
      ),
      set: [unsubscribed_at: event.unsubscribed_at, updated_at: DateTime.utc_now()]
    )
  end)

  project(%UserCheckpoint{} = event, _metadata, fn multi ->
    # Legacy: upsert subscriptions from old monolithic checkpoint
    Enum.reduce(event.subscriptions, multi, fn {feed, sub}, acc ->
      Ecto.Multi.insert(
        acc,
        {:subscription, feed},
        %Subscription{
          user_id: event.user_id,
          rss_source_feed: feed,
          rss_source_id: sub.rss_source_id,
          subscribed_at: parse_datetime(sub.subscribed_at),
          unsubscribed_at: parse_datetime(sub.unsubscribed_at)
        },
        on_conflict: {:replace_all_except, [:id, :inserted_at]},
        conflict_target: [:user_id, :rss_source_feed]
      )
    end)
  end)

  project(%SubscriptionCheckpoint{} = event, _metadata, fn multi ->
    Enum.reduce(event.subscriptions || %{}, multi, fn {feed, sub}, acc ->
      Ecto.Multi.insert(
        acc,
        {:subscription, feed},
        %Subscription{
          user_id: event.user_id,
          rss_source_feed: feed,
          rss_source_id: Map.get(sub, :rss_source_id),
          subscribed_at: parse_datetime(Map.get(sub, :subscribed_at)),
          unsubscribed_at: parse_datetime(Map.get(sub, :unsubscribed_at))
        },
        on_conflict: {:replace_all_except, [:id, :inserted_at]},
        conflict_target: [:user_id, :rss_source_feed]
      )
    end)
  end)

  # Parse ISO8601 datetime string to DateTime struct
  # Truncate microseconds to :second (Ecto :utc_datetime expects 0 microseconds)
  defp parse_datetime(nil), do: nil

  defp parse_datetime(dt) when is_struct(dt, DateTime) do
    DateTime.truncate(dt, :second)
  end

  defp parse_datetime(dt_string) when is_binary(dt_string) do
    case DateTime.from_iso8601(dt_string) do
      {:ok, datetime, _offset} -> DateTime.truncate(datetime, :second)
      {:error, _} -> nil
    end
  end
end
