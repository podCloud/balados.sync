defmodule BaladosSyncCore.ProcessManagers.AddFeedToDefaultCollection do
  @moduledoc """
  Event Handler: Ensures feed is added to default collection on subscription.

  Listens to UserSubscribed events and:
  1. Creates default "all" collection if it doesn't exist
  2. Adds the subscribed feed to the default collection

  This ensures proper Event Sourcing: FeedAddedToCollection events are emitted
  for all feed additions, including automatic additions to the default collection.

  ## CQRS Flow

  1. Subscribe command → UserSubscribed event
  2. This handler listens to UserSubscribed
  3. Handler ensures default collection exists (CreateCollection command)
  4. Handler dispatches AddFeedToCollection command
  5. Events are persisted and projections updated
  """

  use Commanded.Event.Handler,
    application: BaladosSyncCore.Application,
    name: __MODULE__,
    start_from: :origin

  alias BaladosSyncCore.Commands.{CreateCollection, AddFeedToCollection}
  alias BaladosSyncCore.Events.UserSubscribed
  alias BaladosSyncCore.Dispatcher.Router

  def handle(%UserSubscribed{} = event, _metadata) do
    default_col_id = generate_default_collection_id(event.user_id)

    # Step 1: Ensure default collection exists
    ensure_default_collection_exists(event.user_id, default_col_id, event.event_infos)

    # Step 2: Add feed to default collection
    add_feed_to_collection(
      event.user_id,
      default_col_id,
      event.rss_source_feed,
      event.event_infos
    )
  end

  # Tries to create default collection, ignores if already exists
  defp ensure_default_collection_exists(user_id, collection_id, event_infos) do
    cmd = %CreateCollection{
      user_id: user_id,
      collection_id: collection_id,
      title: "All Subscriptions",
      is_default: true,
      event_infos: event_infos || %{}
    }

    case Router.dispatch(cmd) do
      :ok ->
        # Collection created successfully
        :ok

      {:error, :default_collection_already_exists} ->
        # Collection already exists (already created in previous subscription)
        # This is expected and not an error
        :ok

      error ->
        # Log unexpected errors but don't block the handler
        # The AddFeedToCollection will still be attempted
        error
    end
  end

  # Dispatches AddFeedToCollection command
  defp add_feed_to_collection(user_id, collection_id, rss_source_feed, event_infos) do
    cmd = %AddFeedToCollection{
      user_id: user_id,
      collection_id: collection_id,
      rss_source_feed: rss_source_feed,
      event_infos: event_infos || %{}
    }

    Router.dispatch(cmd)
  end

  # Generate deterministic ID for default collection based on user_id
  defp generate_default_collection_id(user_id) do
    :crypto.hash(:sha256, "default-collection-#{user_id}")
    |> Base.encode16(case: :lower)
    |> String.slice(0..31)
  end
end
