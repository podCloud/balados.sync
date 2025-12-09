defmodule BaladosSyncWeb.PlayTokenHelperExpirationTest do
  use BaladosSyncWeb.DataCase, async: true

  alias BaladosSyncWeb.PlayTokenHelper
  alias BaladosSyncProjections.Schemas.PlayToken
  alias BaladosSyncCore.SystemRepo
  import Ecto.Query

  setup do
    user_id = "user-#{System.unique_integer()}"
    {:ok, user_id: user_id}
  end

  describe "create_balados_web_token/2 with default expiration" do
    test "creates token with default expiration (365 days)", %{user_id: user_id} do
      {:ok, token_string} = PlayTokenHelper.create_balados_web_token(user_id)

      assert is_binary(token_string)

      # Verify token was created with expiration
      token_record =
        SystemRepo.one(from(t in PlayToken, where: t.token == ^token_string, limit: 1))

      assert token_record
      assert token_record.expires_at
      assert not PlayToken.expired?(token_record)
    end
  end

  describe "create_balados_web_token/2 with custom expiration" do
    test "creates token with custom expiration days", %{user_id: user_id} do
      custom_days = 30

      {:ok, token_string} =
        PlayTokenHelper.create_balados_web_token(user_id, expiration_days: custom_days)

      assert is_binary(token_string)

      # Verify token was created with custom expiration
      token_record =
        SystemRepo.one(from(t in PlayToken, where: t.token == ^token_string, limit: 1))

      assert token_record
      assert token_record.expires_at

      # Check that expiration is approximately 30 days from now
      expected_expiration = DateTime.utc_now() |> DateTime.add(custom_days * 86400, :second)
      time_diff = DateTime.diff(token_record.expires_at, expected_expiration)

      # Allow 5 second tolerance
      assert time_diff >= -5 and time_diff <= 5
    end
  end

  describe "create_balados_web_token/2 with no expiration" do
    test "creates token without expiration when expiration_days is 0", %{user_id: user_id} do
      {:ok, token_string} = PlayTokenHelper.create_balados_web_token(user_id, expiration_days: 0)

      assert is_binary(token_string)

      # Verify token was created WITHOUT expiration
      token_record =
        SystemRepo.one(from(t in PlayToken, where: t.token == ^token_string, limit: 1))

      assert token_record
      assert is_nil(token_record.expires_at)
    end
  end

  describe "create_websocket_token/2 with default expiration" do
    test "creates token with default expiration (365 days)", %{user_id: user_id} do
      {:ok, token_string} = PlayTokenHelper.create_websocket_token(user_id)

      assert is_binary(token_string)

      # Verify token was created with expiration
      token_record =
        SystemRepo.one(from(t in PlayToken, where: t.token == ^token_string, limit: 1))

      assert token_record
      assert token_record.expires_at
      assert not PlayToken.expired?(token_record)
    end
  end

  describe "create_websocket_token/2 with custom expiration" do
    test "creates token with custom expiration days", %{user_id: user_id} do
      custom_days = 60

      {:ok, token_string} =
        PlayTokenHelper.create_websocket_token(user_id, expiration_days: custom_days)

      assert is_binary(token_string)

      # Verify token was created with custom expiration
      token_record =
        SystemRepo.one(from(t in PlayToken, where: t.token == ^token_string, limit: 1))

      assert token_record
      assert token_record.expires_at

      # Check that expiration is approximately 60 days from now
      expected_expiration = DateTime.utc_now() |> DateTime.add(custom_days * 86400, :second)
      time_diff = DateTime.diff(token_record.expires_at, expected_expiration)

      # Allow 5 second tolerance
      assert time_diff >= -5 and time_diff <= 5
    end
  end
end
