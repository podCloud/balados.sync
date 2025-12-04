defmodule BaladosSyncWeb.LiveWebSocketIntegrationTest do
  use BaladosSyncWeb.ConnCase

  alias BaladosSyncProjections.Schemas.PlayToken
  alias BaladosSyncCore.SystemRepo

  setup do
    # Create a test PlayToken for integration testing
    token = PlayToken.generate_token()

    play_token = %PlayToken{
      user_id: "test_user_123",
      token: token,
      name: "Integration Test Token"
    }

    {:ok, _} = SystemRepo.insert(play_token)

    {:ok, token: token, user_id: "test_user_123"}
  end

  describe "WebSocket connection and authentication" do
    test "successfully authenticates with valid PlayToken", %{token: token} do
      # Send auth message
      auth_msg = Jason.encode!(%{"type" => "auth", "token" => token})

      # Parse response
      response = Jason.decode!(BaladosSyncWeb.LiveWebSocket.MessageHandler.handle_message(
        auth_msg,
        BaladosSyncWeb.LiveWebSocket.State.new()
      ) |> elem(1))

      assert response["status"] == "ok"
      assert response["data"]["user_id"] == "test_user_123"
    end

    test "rejects invalid PlayToken", %{} do
      invalid_token = "invalid_token_xyz"

      auth_msg = Jason.encode!(%{"type" => "auth", "token" => invalid_token})

      response = Jason.decode!(BaladosSyncWeb.LiveWebSocket.MessageHandler.handle_message(
        auth_msg,
        BaladosSyncWeb.LiveWebSocket.State.new()
      ) |> elem(1))

      assert response["status"] == "error"
      assert response["error"]["code"] == "INVALID_TOKEN"
    end

    test "prevents unauthenticated record_play messages" do
      play_msg = Jason.encode!(%{
        "type" => "record_play",
        "feed" => "encoded_feed",
        "item" => "encoded_item",
        "position" => 60,
        "played" => false
      })

      response = Jason.decode!(BaladosSyncWeb.LiveWebSocket.MessageHandler.handle_message(
        play_msg,
        BaladosSyncWeb.LiveWebSocket.State.new()
      ) |> elem(1))

      assert response["status"] == "error"
      assert response["error"]["code"] == "UNAUTHENTICATED"
    end

    test "validates message JSON format", %{token: token} do
      invalid_json = "{invalid json"

      response = Jason.decode!(BaladosSyncWeb.LiveWebSocket.MessageHandler.handle_message(
        invalid_json,
        BaladosSyncWeb.LiveWebSocket.State.new()
      ) |> elem(1))

      assert response["status"] == "error"
      assert response["error"]["code"] == "INVALID_JSON"
    end

    test "rejects authentication after already authenticated", %{token: token} do
      auth_msg = Jason.encode!(%{"type" => "auth", "token" => token})

      # First authentication
      {:ok, _response, state} = BaladosSyncWeb.LiveWebSocket.MessageHandler.handle_message(
        auth_msg,
        BaladosSyncWeb.LiveWebSocket.State.new()
      )

      assert BaladosSyncWeb.LiveWebSocket.State.authenticated?(state)

      # Try to authenticate again
      response = Jason.decode!(BaladosSyncWeb.LiveWebSocket.MessageHandler.handle_message(
        auth_msg,
        state
      ) |> elem(1))

      assert response["status"] == "error"
      assert response["error"]["code"] == "INVALID_STATE"
    end
  end

  describe "record_play message validation" do
    setup %{token: token} do
      auth_msg = Jason.encode!(%{"type" => "auth", "token" => token})

      {:ok, _response, state} = BaladosSyncWeb.LiveWebSocket.MessageHandler.handle_message(
        auth_msg,
        BaladosSyncWeb.LiveWebSocket.State.new()
      )

      {:ok, authenticated_state: state}
    end

    test "accepts valid record_play message", %{authenticated_state: state} do
      play_msg = Jason.encode!(%{
        "type" => "record_play",
        "feed" => "base64_encoded_feed",
        "item" => "base64_encoded_item",
        "position" => 120,
        "played" => false
      })

      {:ok, response, _new_state} = BaladosSyncWeb.LiveWebSocket.MessageHandler.handle_message(
        play_msg,
        state
      )

      parsed = Jason.decode!(response)
      assert parsed["status"] == "ok"
    end

    test "rejects record_play without required feed field", %{authenticated_state: state} do
      play_msg = Jason.encode!(%{
        "type" => "record_play",
        "item" => "encoded_item",
        "position" => 60,
        "played" => false
      })

      response = Jason.decode!(BaladosSyncWeb.LiveWebSocket.MessageHandler.handle_message(
        play_msg,
        state
      ) |> elem(1))

      assert response["status"] == "error"
      assert response["error"]["code"] == "MISSING_FIELDS"
    end

    test "rejects record_play without required item field", %{authenticated_state: state} do
      play_msg = Jason.encode!(%{
        "type" => "record_play",
        "feed" => "encoded_feed",
        "position" => 60,
        "played" => false
      })

      response = Jason.decode!(BaladosSyncWeb.LiveWebSocket.MessageHandler.handle_message(
        play_msg,
        state
      ) |> elem(1))

      assert response["status"] == "error"
      assert response["error"]["code"] == "MISSING_FIELDS"
    end

    test "provides default position and played values", %{authenticated_state: state} do
      play_msg = Jason.encode!(%{
        "type" => "record_play",
        "feed" => "encoded_feed",
        "item" => "encoded_item"
      })

      {:ok, response, _new_state} = BaladosSyncWeb.LiveWebSocket.MessageHandler.handle_message(
        play_msg,
        state
      )

      parsed = Jason.decode!(response)
      assert parsed["status"] == "ok"
    end

    test "rejects invalid position (non-integer)", %{authenticated_state: state} do
      play_msg = Jason.encode!(%{
        "type" => "record_play",
        "feed" => "encoded_feed",
        "item" => "encoded_item",
        "position" => "not_a_number",
        "played" => false
      })

      response = Jason.decode!(BaladosSyncWeb.LiveWebSocket.MessageHandler.handle_message(
        play_msg,
        state
      ) |> elem(1))

      assert response["status"] == "error"
      assert response["error"]["code"] == "INVALID_POSITION"
    end

    test "rejects invalid played value (non-boolean)", %{authenticated_state: state} do
      play_msg = Jason.encode!(%{
        "type" => "record_play",
        "feed" => "encoded_feed",
        "item" => "encoded_item",
        "position" => 60,
        "played" => "not_a_boolean"
      })

      response = Jason.decode!(BaladosSyncWeb.LiveWebSocket.MessageHandler.handle_message(
        play_msg,
        state
      ) |> elem(1))

      assert response["status"] == "error"
      assert response["error"]["code"] == "INVALID_PLAYED"
    end
  end

  describe "state transitions" do
    setup %{token: token} do
      auth_msg = Jason.encode!(%{"type" => "auth", "token" => token})

      {:ok, _response, state} = BaladosSyncWeb.LiveWebSocket.MessageHandler.handle_message(
        auth_msg,
        BaladosSyncWeb.LiveWebSocket.State.new()
      )

      {:ok, authenticated_state: state}
    end

    test "state is authenticated after successful auth", %{authenticated_state: state} do
      assert BaladosSyncWeb.LiveWebSocket.State.authenticated?(state)
      assert state.user_id == "test_user_123"
      assert state.token_type == :play_token
    end

    test "state is touched after processing message", %{authenticated_state: state} do
      before_touch = state.last_activity

      play_msg = Jason.encode!(%{
        "type" => "record_play",
        "feed" => "encoded_feed",
        "item" => "encoded_item"
      })

      {:ok, _response, new_state} = BaladosSyncWeb.LiveWebSocket.MessageHandler.handle_message(
        play_msg,
        state
      )

      # Verify that state was updated
      assert new_state.last_activity != before_touch or
             DateTime.compare(new_state.last_activity, before_touch) == :gt
    end
  end

  describe "error handling" do
    setup %{token: token} do
      auth_msg = Jason.encode!(%{"type" => "auth", "token" => token})

      {:ok, _response, state} = BaladosSyncWeb.LiveWebSocket.MessageHandler.handle_message(
        auth_msg,
        BaladosSyncWeb.LiveWebSocket.State.new()
      )

      {:ok, authenticated_state: state}
    end

    test "unknown message type returns error", %{authenticated_state: state} do
      unknown_msg = Jason.encode!(%{"type" => "unknown_type"})

      response = Jason.decode!(BaladosSyncWeb.LiveWebSocket.MessageHandler.handle_message(
        unknown_msg,
        state
      ) |> elem(1))

      assert response["status"] == "error"
      assert response["error"]["code"] == "INVALID_TYPE"
    end

    test "malformed message returns error", %{authenticated_state: state} do
      malformed_msg = Jason.encode!(%{"no_type_field" => "test"})

      response = Jason.decode!(BaladosSyncWeb.LiveWebSocket.MessageHandler.handle_message(
        malformed_msg,
        state
      ) |> elem(1))

      assert response["status"] == "error"
    end
  end
end
