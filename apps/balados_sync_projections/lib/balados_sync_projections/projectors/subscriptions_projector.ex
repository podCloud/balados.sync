defmodule BaladosSyncProjections.Projectors.SubscriptionsProjector do
  use Commanded.Projections.Ecto,
    application: BaladosSyncCore.Dispatcher,
    repo: BaladosSyncProjections.ProjectionsRepo,
    name: "SubscriptionsProjector"

  require Logger
  import Ecto.Query

  alias BaladosSyncCore.Events.{UserSubscribed, UserUnsubscribed, UserCheckpoint}
  alias BaladosSyncProjections.Schemas.Subscription

  project(%UserSubscribed{} = event, _metadata, fn multi ->
    # Insérer la subscription immédiatement (ne pas bloquer sur fetch RSS)
    subscribed_at = parse_datetime(event.subscribed_at)

    multi =
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

    # Déclencher l'enrichissement async des métadonnées
    Ecto.Multi.run(multi, :enrich_metadata, fn _repo, _changes ->
      Task.start(fn ->
        enrich_subscription_metadata(event.rss_source_feed)
      end)

      {:ok, :started}
    end)
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
    # Upsert de toutes les subscriptions du checkpoint
    multi =
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

    multi
  end)

  # Enrichissement async des métadonnées de subscription
  defp enrich_subscription_metadata(encoded_feed) do
    try do
      with {:ok, feed_url} <- Base.decode64(encoded_feed),
           {:ok, metadata} <- BaladosSyncWeb.RssCache.get_feed_metadata(feed_url) do
        # Mettre à jour toutes les subscriptions de ce flux avec le titre
        from(s in Subscription, where: s.rss_source_feed == ^encoded_feed)
        |> BaladosSyncProjections.ProjectionsRepo.update_all(
          set: [rss_feed_title: metadata.title, updated_at: DateTime.utc_now()]
        )

        Logger.debug("Enriched subscription metadata for feed: #{metadata.title}")
      else
        _ -> :ok
      end
    rescue
      e ->
        Logger.error("Failed to enrich subscription metadata: #{inspect(e)}")
    end
  end

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
