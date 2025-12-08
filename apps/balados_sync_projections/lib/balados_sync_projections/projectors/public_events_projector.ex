defmodule BaladosSyncProjections.Projectors.PublicEventsProjector do
  use Commanded.Projections.Ecto,
    application: BaladosSyncCore.Dispatcher,
    repo: BaladosSyncProjections.ProjectionsRepo,
    name: "PublicEventsProjector"

  import Ecto.Query

  alias BaladosSyncCore.Events.{
    UserSubscribed,
    PlayRecorded,
    PrivacyChanged,
    EventsRemoved
  }

  alias BaladosSyncProjections.Schemas.{PublicEvent, UserPrivacy}

  # Helper pour récupérer la privacy actuelle pour un user/feed/item
  defp get_privacy(repo, user_id, feed, item) do
    # Privacy la plus spécifique : item > feed > user
    # Check with Elixir is_nil to avoid type inference issues with fragments
    item_condition = if is_nil(item), do: true, else: false
    feed_condition = if is_nil(feed), do: true, else: false

    query =
      from(p in UserPrivacy,
        where: p.user_id == ^user_id
      )

    query =
      if item_condition do
        from(p in query, where: is_nil(p.rss_source_item))
      else
        from(p in query, where: p.rss_source_item == ^item or is_nil(p.rss_source_item))
      end

    query =
      if feed_condition do
        from(p in query, where: is_nil(p.rss_source_feed))
      else
        from(p in query, where: p.rss_source_feed == ^feed or is_nil(p.rss_source_feed))
      end

    query =
      from(p in query,
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

    repo.one(query) || :public
  end

  project(%UserSubscribed{} = event, _metadata, fn multi ->
    Ecto.Multi.run(multi, :public_event, fn repo, _changes ->
      privacy = get_privacy(repo, event.user_id, event.rss_source_feed, nil)

      if privacy in [:public, :anonymous] do
        repo.insert(%PublicEvent{
          # Gardé même si anonymous
          user_id: event.user_id,
          event_type: "subscribe",
          rss_source_feed: event.rss_source_feed,
          privacy: to_string(privacy),
          event_data: %{},
          event_timestamp: parse_datetime(event.timestamp)
        })
      else
        {:ok, nil}
      end
    end)
  end)

  project(%PlayRecorded{} = event, _metadata, fn multi ->
    Ecto.Multi.run(multi, :public_event, fn repo, _changes ->
      privacy = get_privacy(repo, event.user_id, event.rss_source_feed, event.rss_source_item)

      if privacy in [:public, :anonymous] do
        repo.insert(%PublicEvent{
          # Gardé même si anonymous
          user_id: event.user_id,
          event_type: "play",
          rss_source_feed: event.rss_source_feed,
          rss_source_item: event.rss_source_item,
          privacy: to_string(privacy),
          event_data: %{position: event.position, played: event.played},
          event_timestamp: parse_datetime(event.timestamp)
        })
      else
        {:ok, nil}
      end
    end)
  end)

  project(%PrivacyChanged{} = event, _metadata, fn multi ->
    # Convert privacy string to atom if needed
    privacy_atom =
      case event.privacy do
        atom when is_atom(atom) -> atom
        string when is_binary(string) -> String.to_atom(string)
      end

    # Mise à jour de la table privacy
    multi =
      Ecto.Multi.insert(
        multi,
        :upsert_privacy,
        %UserPrivacy{
          user_id: event.user_id,
          rss_source_feed: event.rss_source_feed,
          rss_source_item: event.rss_source_item,
          privacy: to_string(privacy_atom)
        },
        on_conflict: {:replace, [:privacy, :updated_at]},
        conflict_target: [:user_id, :rss_source_feed, :rss_source_item]
      )

    # Mise à jour des public_events selon la nouvelle privacy
    case {privacy_atom, event.rss_source_feed, event.rss_source_item} do
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

      {:private, _feed, item} when not is_nil(item) ->
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

      {:anonymous, _feed, item} when not is_nil(item) ->
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
