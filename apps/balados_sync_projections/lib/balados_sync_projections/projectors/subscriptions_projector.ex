defmodule BaladosSyncProjections.Projectors.SubscriptionsProjector do
  use Commanded.Projections.Ecto,
    application: BaladosSyncCore.App,
    repo: BaladosSyncProjections.Repo,
    name: "SubscriptionsProjector"

  alias BaladosSyncCore.Events.{UserSubscribed, UserUnsubscribed, UserCheckpoint}
  alias BaladosSyncProjections.Schemas.Subscription

  project(%UserSubscribed{} = event, _metadata, fn multi ->
    Ecto.Multi.insert(
      multi,
      :subscription,
      %Subscription{
        user_id: event.user_id,
        rss_source_feed: event.rss_source_feed,
        rss_source_id: event.rss_source_id,
        subscribed_at: event.subscribed_at,
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
            subscribed_at: sub.subscribed_at,
            unsubscribed_at: sub.unsubscribed_at
          },
          on_conflict: {:replace_all_except, [:id, :inserted_at]},
          conflict_target: [:user_id, :rss_source_feed]
        )
      end)

    multi
  end)
end
