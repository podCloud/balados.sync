defmodule BaladosSyncJobs.PlayTokenCleanupWorkerTest do
  use BaladosSyncJobs.DataCase, async: true

  alias BaladosSyncJobs.PlayTokenCleanupWorker
  alias BaladosSyncProjections.Schemas.PlayToken
  alias BaladosSyncCore.SystemRepo
  import Ecto.Query

  describe "perform/0" do
    test "deletes tokens that expired more than 30 days ago" do
      user_id = "user-#{System.unique_integer()}"

      # Token expired 31 days ago (should be deleted)
      old_expired_time =
        DateTime.add(DateTime.utc_now(), -(31 * 86400), :second)
        |> DateTime.truncate(:second)

      old_token = %PlayToken{
        user_id: user_id,
        token: "old-expired-#{System.unique_integer()}",
        name: "Old Token",
        expires_at: old_expired_time
      }

      {:ok, _} = SystemRepo.insert(old_token)

      # Token expired 10 days ago (should NOT be deleted)
      recent_expired_time =
        DateTime.add(DateTime.utc_now(), -(10 * 86400), :second)
        |> DateTime.truncate(:second)

      recent_token = %PlayToken{
        user_id: user_id,
        token: "recent-expired-#{System.unique_integer()}",
        name: "Recent Token",
        expires_at: recent_expired_time
      }

      {:ok, _} = SystemRepo.insert(recent_token)

      # Token not expired (should NOT be deleted)
      future_time =
        DateTime.add(DateTime.utc_now(), 86400, :second)
        |> DateTime.truncate(:second)

      future_token = %PlayToken{
        user_id: user_id,
        token: "future-#{System.unique_integer()}",
        name: "Future Token",
        expires_at: future_time
      }

      {:ok, _} = SystemRepo.insert(future_token)

      # Run cleanup
      PlayTokenCleanupWorker.perform()

      # Verify old token was deleted
      assert nil ==
               SystemRepo.one(
                 from(t in PlayToken, where: t.token == ^old_token.token, limit: 1)
               )

      # Verify recent token still exists
      assert SystemRepo.one(
               from(t in PlayToken, where: t.token == ^recent_token.token, limit: 1)
             )

      # Verify future token still exists
      assert SystemRepo.one(
               from(t in PlayToken, where: t.token == ^future_token.token, limit: 1)
             )
    end

    test "does not delete revoked tokens" do
      user_id = "user-#{System.unique_integer()}"

      # Token expired 31 days ago but also revoked
      old_expired_time =
        DateTime.add(DateTime.utc_now(), -(31 * 86400), :second)
        |> DateTime.truncate(:second)

      revoked_time = DateTime.utc_now() |> DateTime.truncate(:second)

      revoked_token = %PlayToken{
        user_id: user_id,
        token: "revoked-#{System.unique_integer()}",
        name: "Revoked Token",
        expires_at: old_expired_time,
        revoked_at: revoked_time
      }

      {:ok, _} = SystemRepo.insert(revoked_token)

      # Run cleanup
      PlayTokenCleanupWorker.perform()

      # Verify revoked token still exists (not deleted by cleanup)
      # Revoked tokens are deleted by admin, not by this worker
      assert SystemRepo.one(
               from(t in PlayToken, where: t.token == ^revoked_token.token, limit: 1)
             )
    end

    test "does not delete tokens without expiration" do
      user_id = "user-#{System.unique_integer()}"

      # Token with no expiration (backward compatibility)
      no_expiration_token = %PlayToken{
        user_id: user_id,
        token: "no-expiration-#{System.unique_integer()}",
        name: "No Expiration Token",
        expires_at: nil
      }

      {:ok, _} = SystemRepo.insert(no_expiration_token)

      # Run cleanup
      PlayTokenCleanupWorker.perform()

      # Verify token still exists
      assert SystemRepo.one(
               from(t in PlayToken, where: t.token == ^no_expiration_token.token, limit: 1)
             )
    end
  end
end
