defmodule BaladosSyncJobs.OwnershipClaimCleanupWorker do
  @moduledoc """
  Background worker for expiring and cleaning up old podcast ownership claims.

  This worker performs two tasks:
  1. Expires pending claims that have passed their expiration date
  2. Deletes old non-pending claims after a retention period

  Runs daily to maintain database hygiene for the ownership verification system.
  """

  require Logger
  import Ecto.Query

  alias BaladosSyncCore.SystemRepo
  alias BaladosSyncProjections.Schemas.PodcastOwnershipClaim

  @default_retention_days 30

  def perform do
    Logger.info("[OwnershipClaimCleanupWorker] Starting ownership claim cleanup...")

    # First, expire pending claims that have passed their expiration date
    expired_count = expire_pending_claims()
    Logger.info("[OwnershipClaimCleanupWorker] Expired #{expired_count} pending claims")

    # Then, delete old non-pending claims
    retention_days = get_retention_days()
    cleanup_threshold = DateTime.add(DateTime.utc_now(), -retention_days * 86400, :second)

    case delete_old_claims(cleanup_threshold) do
      {:ok, count} ->
        Logger.info(
          "[OwnershipClaimCleanupWorker] Cleaned up #{count} old claims (older than #{retention_days} days)"
        )

      {:error, reason} ->
        Logger.error(
          "[OwnershipClaimCleanupWorker] Failed to cleanup old claims: #{inspect(reason)}"
        )
    end
  end

  @doc """
  Expires pending claims that have passed their expiration date.
  Returns the number of claims expired.
  """
  def expire_pending_claims do
    now = DateTime.utc_now()

    {count, _} =
      PodcastOwnershipClaim
      |> where([c], c.status == "pending" and c.expires_at < ^now)
      |> SystemRepo.update_all(set: [status: "expired", updated_at: now])

    count
  end

  @doc false
  defp delete_old_claims(cutoff_date) do
    try do
      # Delete claims that are not pending and are older than the cutoff
      count =
        from(c in PodcastOwnershipClaim,
          where: c.status != "pending" and c.updated_at < ^cutoff_date
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
    Application.get_env(:balados_sync_jobs, :ownership_claim_retention_days, @default_retention_days)
  end
end
