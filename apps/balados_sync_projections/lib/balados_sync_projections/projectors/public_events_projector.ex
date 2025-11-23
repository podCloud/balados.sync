defmodule BaladosSyncProjections.Projectors.PublicEventsProjector do
  use Commanded.Projections.Ecto,
    application: BaladosSyncCore.Dispatcher,
    repo: BaladosSyncProjections.Repo,
    name: "PublicEventsProjector"

  import Ecto.Query

  alias BaladosSyncCore.Events.{
    UserSubscribed,
    PlayRecorded,
    EpisodeSaved,
    EpisodeShared,
    PrivacyChanged,
    EventsRemoved
  }

  alias BaladosSyncProjections.Schemas.{PublicEvent, UserPrivacy}

  # Helper pour récupérer la privacy actuelle pour un user/feed/item
  defp get_privacy(user_id, feed, item) do
    # Privacy la plus spécifique : item > feed > user
    query =
      from(p in UserPrivacy,
        where: p.user_id == ^user_id,
        where: is_nil(^item) or p.rss_source_item == ^item or is_nil(p.rss_source_item),
        where: is_nil(^feed) or p.rss_source_feed == ^feed or is_nil(p.rss_source_feed),
        order_by: [
          desc:
            fragment(
              "CASE WHEN ? IS NOT NULL THEN 3 WHEN ? IS NOT NULL THEN 2 ELSE 1 END",
              p.rss_source_item,
              p.rss_source_feed
            )
        ],
        limit: 1,
        select: p.privacy
      )

    BaladosSyncProjections.Repo.one(query) || :public
  end

  project(%UserSubscribed{} = event, _metadata, fn multi ->
    privacy = get_privacy(event.user_id, event.rss_source_feed, nil)

    if privacy in [:public, :anonymous] do
      Ecto.Multi.insert(multi, :public_event, %PublicEvent{
        # Gardé même si anonymous
        user_id: event.user_id,
        event_type: "subscribe",
        rss_source_feed: event.rss_source_feed,
        privacy: to_string(privacy),
        event_data: %{},
        event_timestamp: event.timestamp
      })
    else
      multi
    end
  end)

  project(%PlayRecorded{} = event, _metadata, fn multi ->
    privacy = get_privacy(event.user_id, event.rss_source_feed, event.rss_source_item)

    if privacy in [:public, :anonymous] do
      Ecto.Multi.insert(multi, :public_event, %PublicEvent{
        # Gardé même si anonymous
        user_id: event.user_id,
        event_type: "play",
        rss_source_feed: event.rss_source_feed,
        rss_source_item: event.rss_source_item,
        privacy: to_string(privacy),
        event_data: %{position: event.position, played: event.played},
        event_timestamp: event.timestamp
      })
    else
      multi
    end
  end)

  project(%PrivacyChanged{} = event, _metadata, fn multi ->
    # Mise à jour de la table privacy
    multi =
      Ecto.Multi.insert(
        multi,
        :upsert_privacy,
        %UserPrivacy{
          user_id: event.user_id,
          rss_source_feed: event.rss_source_feed,
          rss_source_item: event.rss_source_item,
          privacy: to_string(event.privacy)
        },
        on_conflict: {:replace, [:privacy, :updated_at]},
        conflict_target: [:user_id, :rss_source_feed, :rss_source_item]
      )

    # Mise à jour des public_events selon la nouvelle privacy
    case {event.privacy, event.rss_source_feed, event.rss_source_item} do
      {:private, nil, nil} ->
        # Privacy globale private : supprimer tous les events
        Ecto.Multi.delete_all(
          multi,
          :delete_all_events,
          from(pe in PublicEvent, where: pe.user_id == ^event.user_id)
        )

      {:private, feed, nil} when not is_nil(feed) ->
        # Privacy feed private : supprimer events du feed
        Ecto.Multi.delete_all(
          multi,
          :delete_feed_events,
          from(pe in PublicEvent,
            where: pe.user_id == ^event.user_id and pe.rss_source_feed == ^feed
          )
        )

      {:private, feed, item} when not is_nil(item) ->
        # Privacy item private : supprimer events de l'item
        Ecto.Multi.delete_all(
          multi,
          :delete_item_events,
          from(pe in PublicEvent,
            where: pe.user_id == ^event.user_id and pe.rss_source_item == ^item
          )
        )

      {:anonymous, nil, nil} ->
        # Privacy globale anonymous : mettre à jour tous les events
        Ecto.Multi.update_all(
          multi,
          :anonymize_all,
          from(pe in PublicEvent, where: pe.user_id == ^event.user_id),
          set: [privacy: "anonymous"]
        )

      {:anonymous, feed, nil} when not is_nil(feed) ->
        Ecto.Multi.update_all(
          multi,
          :anonymize_feed,
          from(pe in PublicEvent,
            where: pe.user_id == ^event.user_id and pe.rss_source_feed == ^feed
          ),
          set: [privacy: "anonymous"]
        )

      {:anonymous, feed, item} when not is_nil(item) ->
        Ecto.Multi.update_all(
          multi,
          :anonymize_item,
          from(pe in PublicEvent,
            where: pe.user_id == ^event.user_id and pe.rss_source_item == ^item
          ),
          set: [privacy: "anonymous"]
        )

      {:public, _, _} ->
        # Passage en public : on garde tel quel
        multi
    end
  end)

  project(%EventsRemoved{} = event, _metadata, fn multi ->
    query = from(pe in PublicEvent, where: pe.user_id == ^event.user_id)

    query =
      if event.rss_source_feed do
        from(pe in query, where: pe.rss_source_feed == ^event.rss_source_feed)
      else
        query
      end

    query =
      if event.rss_source_item do
        from(pe in query, where: pe.rss_source_item == ^event.rss_source_item)
      else
        query
      end

    Ecto.Multi.delete_all(multi, :delete_events, query)
  end)
end
