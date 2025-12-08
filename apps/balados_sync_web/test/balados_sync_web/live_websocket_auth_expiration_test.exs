defmodule BaladosSyncWeb.LiveWebSocket.AuthExpirationTest do
  use BaladosSyncWeb.DataCase, async: true

  alias BaladosSyncWeb.LiveWebSocket.Auth
  alias BaladosSyncProjections.Schemas.PlayToken
  alias BaladosSyncCore.SystemRepo

  describe "authenticate/1 with expired PlayToken" do
    setup do
      # Create a token
      token_string = PlayToken.generate_token()
      user_id = "user-#{System.unique_integer()}"

      past_time = DateTime.add(DateTime.utc_now(), -3600, :second) |> DateTime.truncate(:second)

      play_token = %PlayToken{
        user_id: user_id,
        token: token_string,
        name: "Balados Web",
        expires_at: past_time
      }

      {:ok, _} = SystemRepo.insert(play_token)

      {:ok, token_string: token_string, user_id: user_id}
    end

    test "returns :token_expired when token has expired", %{token_string: token_string} do
      assert {:error, :token_expired} = Auth.authenticate(token_string)
    end
  end

  describe "authenticate/1 with valid PlayToken" do
    setup do
      # Create a token
      token_string = PlayToken.generate_token()
      user_id = "user-#{System.unique_integer()}"

      future_time =
        DateTime.add(DateTime.utc_now(), 86400, :second) |> DateTime.truncate(:second)

      play_token = %PlayToken{
        user_id: user_id,
        token: token_string,
        name: "Balados Web",
        expires_at: future_time
      }

      {:ok, _} = SystemRepo.insert(play_token)

      {:ok, token_string: token_string, user_id: user_id}
    end

    test "returns :ok with user_id when token is valid and not expired", %{
      token_string: token_string,
      user_id: user_id
    } do
      assert {:ok, returned_user_id, :play_token} = Auth.authenticate(token_string)
      assert returned_user_id == user_id
    end
  end

  describe "authenticate/1 with token without expiration" do
    setup do
      # Create a token without expiration (backward compatibility)
      token_string = PlayToken.generate_token()
      user_id = "user-#{System.unique_integer()}"

      play_token = %PlayToken{
        user_id: user_id,
        token: token_string,
        name: "Balados Web",
        expires_at: nil
      }

      {:ok, _} = SystemRepo.insert(play_token)

      {:ok, token_string: token_string, user_id: user_id}
    end

    test "returns :ok (backward compatible - no expiration means token never expires)", %{
      token_string: token_string,
      user_id: user_id
    } do
      assert {:ok, returned_user_id, :play_token} = Auth.authenticate(token_string)
      assert returned_user_id == user_id
    end
  end

  describe "authenticate/1 with revoked token" do
    setup do
      # Create a token
      token_string = PlayToken.generate_token()
      user_id = "user-#{System.unique_integer()}"

      future_time =
        DateTime.add(DateTime.utc_now(), 86400, :second) |> DateTime.truncate(:second)

      revoked_time = DateTime.utc_now() |> DateTime.truncate(:second)

      play_token = %PlayToken{
        user_id: user_id,
        token: token_string,
        name: "Balados Web",
        expires_at: future_time,
        revoked_at: revoked_time
      }

      {:ok, _} = SystemRepo.insert(play_token)

      {:ok, token_string: token_string}
    end

    test "returns :invalid_token when token is revoked (revoked takes precedence)", %{
      token_string: token_string
    } do
      assert {:error, :invalid_token} = Auth.authenticate(token_string)
    end
  end
end
