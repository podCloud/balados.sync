defmodule BaladosSyncCore.Middleware.ValidateSubscription do
  @moduledoc """
  Commanded middleware that validates feed subscription before AddFeedToCollection.

  After splitting the User aggregate into bounded contexts, the Collection aggregate
  no longer has access to subscription state. This middleware queries the subscriptions
  projection to enforce the business rule: feeds must be subscribed before being added
  to a collection.
  """

  @behaviour Commanded.Middleware

  alias BaladosSyncCore.Commands.AddFeedToCollection

  import Ecto.Query

  def before_dispatch(%Commanded.Middleware.Pipeline{command: %AddFeedToCollection{} = cmd} = pipeline) do
    repo = repo()

    # Uses raw table name with prefix to avoid compile-time dependency on
    # BaladosSyncProjections.Schemas.Subscription (core compiles before projections).
    query =
      from(s in "subscriptions",
        where: s.user_id == ^cmd.user_id and s.rss_source_feed == ^cmd.rss_source_feed,
        where: is_nil(s.unsubscribed_at),
        select: s.id
      )

    case repo.one(query, prefix: "users") do
      nil ->
        pipeline
        |> Commanded.Middleware.Pipeline.respond({:error, :feed_not_subscribed})
        |> Commanded.Middleware.Pipeline.halt()

      _id ->
        pipeline
    end
  end

  def before_dispatch(pipeline), do: pipeline

  def after_dispatch(pipeline), do: pipeline
  def after_failure(pipeline), do: pipeline

  defp repo do
    Application.get_env(:balados_sync_core, :projections_repo, BaladosSyncProjections.ProjectionsRepo)
  end
end
