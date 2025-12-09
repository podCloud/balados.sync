defmodule BaladosSyncJobs.PlayTokenCleanupWorker do
  @moduledoc """
  Background worker for cleaning up expired PlayTokens.

  Runs daily to delete tokens that have been expired for more than
  the configured retention period (default: 30 days).

  This helps reduce database size and removes stale tokens.
  """

  require Logger
  import Ecto.Query

  alias BaladosSyncCore.SystemRepo
  alias BaladosSyncProjections.Schemas.PlayToken

  @default_retention_days 30

  def perform do
    Logger.info("[PlayTokenCleanupWorker] Starting expired token cleanup...")

    retention_days = get_retention_days()
    cleanup_threshold = DateTime.add(DateTime.utc_now(), -retention_days * 86400, :second)

    case delete_expired_tokens(cleanup_threshold) do
      {:ok, count} ->
        Logger.info(
          "[PlayTokenCleanupWorker] Cleaned up #{count} expired tokens (older than #{retention_days} days)"
        )

      {:error, reason} ->
        Logger.error(
          "[PlayTokenCleanupWorker] Failed to cleanup expired tokens: #{inspect(reason)}"
        )
    end
  end

  @doc false
  defp delete_expired_tokens(cutoff_date) do
    try do
      count =
        from(t in PlayToken,
          where:
            not is_nil(t.expires_at) and t.expires_at < ^cutoff_date and
              is_nil(t.revoked_at)
        )
        |> SystemRepo.delete_all()
        |> elem(0)

      {:ok, count}
    rescue
      e ->
        {:error, e}
    end
  end

  @doc false
  defp get_retention_days do
    Application.get_env(:balados_sync_jobs, :play_token_retention_days, @default_retention_days)
  end
end
