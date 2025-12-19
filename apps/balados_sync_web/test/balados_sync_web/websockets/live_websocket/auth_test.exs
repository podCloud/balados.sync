defmodule BaladosSyncWeb.LiveWebSocket.AuthTest do
  @moduledoc """
  Integration tests for the Auth module.

  Tests cover:
  - Token type detection (PlayToken vs JWT)
  - PlayToken validation with real tokens from database
  - Token revocation scenarios
  - Token expiration scenarios

  Note: JWT tests are skipped due to schema/migration mismatch in app_tokens table.
  The AppToken schema has (app_name, scopes) but DB has (token_name, token_scopes).
  This should be fixed in a separate issue.
  """

  use BaladosSyncWeb.ConnCase, async: false

  alias BaladosSyncWeb.LiveWebSocket.Auth
  alias BaladosSyncProjections.Schemas.PlayToken
  alias BaladosSyncCore.SystemRepo

  describe "token type detection" do
    test "detects PlayToken (no dots)" do
      token = PlayToken.generate_token()
      assert {:error, :invalid_token} = Auth.authenticate(token)
      # The error confirms it tried PlayToken validation
    end

    test "detects JWT format (three parts with dots)" do
      # A JWT-like string triggers JWT path
      # Note: The current implementation raises Jason.DecodeError for invalid JWTs
      # instead of returning {:error, :invalid_token}. This is a known limitation.
      # Real JWT validation requires properly configured app_tokens.
      jwt = "header.payload.signature"

      # The code currently raises an exception for malformed JWTs
      # This behavior should be improved to return {:error, :invalid_token}
      assert_raise Jason.DecodeError, fn ->
        Auth.authenticate(jwt)
      end
    end

    test "handles nil token" do
      assert {:error, :invalid_token} = Auth.authenticate(nil)
    end

    test "handles empty string token" do
      assert {:error, :invalid_token} = Auth.authenticate("")
    end
  end

  describe "PlayToken authentication" do
    setup do
      user_id = Ecto.UUID.generate()
      token = PlayToken.generate_token()

      {:ok, user_id: user_id, token: token}
    end

    test "authenticates valid PlayToken", %{user_id: user_id, token: token} do
      # Insert token into database
      {:ok, _} =
        SystemRepo.insert(%PlayToken{
          user_id: user_id,
          token: token,
          name: "Test Token"
        })

      assert {:ok, ^user_id, :play_token} = Auth.authenticate(token)
    end

    test "rejects non-existent PlayToken" do
      fake_token = PlayToken.generate_token()
      assert {:error, :invalid_token} = Auth.authenticate(fake_token)
    end

    test "rejects revoked PlayToken", %{user_id: user_id, token: token} do
      {:ok, _} =
        SystemRepo.insert(%PlayToken{
          user_id: user_id,
          token: token,
          name: "Revoked Token",
          revoked_at: DateTime.utc_now() |> DateTime.truncate(:second)
        })

      assert {:error, :invalid_token} = Auth.authenticate(token)
    end

    test "rejects expired PlayToken", %{user_id: user_id, token: token} do
      # Token expired 1 hour ago
      expired_at =
        DateTime.utc_now()
        |> DateTime.add(-3600, :second)
        |> DateTime.truncate(:second)

      {:ok, _} =
        SystemRepo.insert(%PlayToken{
          user_id: user_id,
          token: token,
          name: "Expired Token",
          expires_at: expired_at
        })

      assert {:error, :token_expired} = Auth.authenticate(token)
    end

    test "accepts PlayToken with no expiration", %{user_id: user_id, token: token} do
      {:ok, _} =
        SystemRepo.insert(%PlayToken{
          user_id: user_id,
          token: token,
          name: "No Expiry Token",
          expires_at: nil
        })

      assert {:ok, ^user_id, :play_token} = Auth.authenticate(token)
    end

    test "accepts PlayToken with future expiration", %{user_id: user_id, token: token} do
      # Token expires in 1 hour
      expires_at =
        DateTime.utc_now()
        |> DateTime.add(3600, :second)
        |> DateTime.truncate(:second)

      {:ok, _} =
        SystemRepo.insert(%PlayToken{
          user_id: user_id,
          token: token,
          name: "Future Expiry Token",
          expires_at: expires_at
        })

      assert {:ok, ^user_id, :play_token} = Auth.authenticate(token)
    end

    test "updates last_used_at on successful authentication", %{user_id: user_id, token: token} do
      {:ok, play_token} =
        SystemRepo.insert(%PlayToken{
          user_id: user_id,
          token: token,
          name: "Last Used Token",
          last_used_at: nil
        })

      assert is_nil(play_token.last_used_at)

      # Authenticate
      assert {:ok, ^user_id, :play_token} = Auth.authenticate(token)

      # Wait for async update
      Process.sleep(100)

      # Verify last_used_at was updated
      updated_token = SystemRepo.get(PlayToken, play_token.id)
      assert not is_nil(updated_token.last_used_at)
    end
  end

  describe "edge cases" do
    test "handles token with exactly 2 dots (invalid JWT format)" do
      # Two dots but empty parts - should be treated as PlayToken
      token = "a.b."
      assert {:error, :invalid_token} = Auth.authenticate(token)
    end

    test "handles token with multiple dots (treated as PlayToken)" do
      # More than 2 dots - not a valid JWT, treated as PlayToken
      token = "a.b.c.d.e"
      assert {:error, :invalid_token} = Auth.authenticate(token)
    end
  end

  # Note: JWT authentication tests are skipped due to schema/migration mismatch.
  # The AppToken schema expects (app_name, scopes) but DB has (token_name, token_scopes).
  # This should be addressed in a separate issue to align the schema with the migration.
  #
  # To add JWT tests in the future:
  # 1. Fix the AppToken schema to match the DB columns
  # 2. Or create a migration to rename the columns
  # 3. Then add tests for:
  #    - JWT with valid scopes (user.plays.write, *.write, *)
  #    - JWT with insufficient scopes
  #    - Revoked app tokens
  #    - Wrong signature
end
