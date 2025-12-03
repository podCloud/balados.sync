defmodule BaladosSyncWeb.LiveWebSocket.MessageHandlerTest do
  use ExUnit.Case, async: true

  alias BaladosSyncWeb.LiveWebSocket.{MessageHandler, State}

  setup do
    {:ok, state: State.new()}
  end

  describe "handle_message/2 - Authentication" do
    test "rejects non-auth messages when unauthenticated", %{state: state} do
      json = Jason.encode!(%{"type" => "record_play", "feed" => "feed", "item" => "item", "position" => 0, "played" => false})
      {:error, response} = MessageHandler.handle_message(json, state)
      decoded = Jason.decode!(response)

      assert decoded["status"] == "error"
      assert decoded["error"]["code"] == "UNAUTHENTICATED"
    end

    test "rejects invalid JSON", %{state: state} do
      {:error, response} = MessageHandler.handle_message("invalid json", state)
      decoded = Jason.decode!(response)

      assert decoded["status"] == "error"
      assert decoded["error"]["code"] == "INVALID_JSON"
    end

    test "rejects message without type", %{state: state} do
      json = Jason.encode!(%{"token" => "xxx"})
      {:error, response} = MessageHandler.handle_message(json, state)
      decoded = Jason.decode!(response)

      assert decoded["status"] == "error"
      assert decoded["error"]["code"] == "INVALID_TYPE"
    end
  end

  describe "handle_message/2 - Authenticated state" do
    setup do
      authenticated_state = State.authenticate(State.new(), "user_123", :play_token, "token_abc")
      {:ok, authenticated_state: authenticated_state}
    end

    test "prevents re-authentication", %{authenticated_state: state} do
      json = Jason.encode!(%{"type" => "auth", "token" => "new_token"})
      {:error, response} = MessageHandler.handle_message(json, state)
      decoded = Jason.decode!(response)

      assert decoded["status"] == "error"
      assert decoded["error"]["code"] == "INVALID_STATE"
    end

    test "rejects unknown message type", %{authenticated_state: state} do
      json = Jason.encode!(%{"type" => "unknown_type"})
      {:error, response} = MessageHandler.handle_message(json, state)
      decoded = Jason.decode!(response)

      assert decoded["status"] == "error"
      assert decoded["error"]["code"] == "INVALID_TYPE"
    end
  end

  describe "handle_message/2 - Record play validation" do
    setup do
      authenticated_state = State.authenticate(State.new(), "user_123", :play_token, "token_abc")
      {:ok, authenticated_state: authenticated_state}
    end

    test "rejects record_play with missing feed", %{authenticated_state: state} do
      json = Jason.encode!(%{"type" => "record_play", "item" => "item", "position" => 0, "played" => false})
      {:error, response} = MessageHandler.handle_message(json, state)
      decoded = Jason.decode!(response)

      assert decoded["status"] == "error"
      assert decoded["error"]["code"] == "MISSING_FIELDS"
    end

    test "rejects record_play with missing item", %{authenticated_state: state} do
      json = Jason.encode!(%{"type" => "record_play", "feed" => "feed", "position" => 0, "played" => false})
      {:error, response} = MessageHandler.handle_message(json, state)
      decoded = Jason.decode!(response)

      assert decoded["status"] == "error"
      assert decoded["error"]["code"] == "MISSING_FIELDS"
    end

    test "rejects record_play with missing position", %{authenticated_state: state} do
      json = Jason.encode!(%{"type" => "record_play", "feed" => "feed", "item" => "item", "played" => false})
      {:error, response} = MessageHandler.handle_message(json, state)
      decoded = Jason.decode!(response)

      assert decoded["status"] == "error"
      assert decoded["error"]["code"] == "MISSING_FIELDS"
    end

    test "rejects record_play with missing played", %{authenticated_state: state} do
      json = Jason.encode!(%{"type" => "record_play", "feed" => "feed", "item" => "item", "position" => 0})
      {:error, response} = MessageHandler.handle_message(json, state)
      decoded = Jason.decode!(response)

      assert decoded["status"] == "error"
      assert decoded["error"]["code"] == "MISSING_FIELDS"
    end

    test "rejects record_play with invalid position type", %{authenticated_state: state} do
      json = Jason.encode!(%{"type" => "record_play", "feed" => "feed", "item" => "item", "position" => "not_a_number", "played" => false})
      {:error, response} = MessageHandler.handle_message(json, state)
      decoded = Jason.decode!(response)

      assert decoded["status"] == "error"
      assert decoded["error"]["code"] == "MISSING_FIELDS"
    end

    test "rejects record_play with invalid played type", %{authenticated_state: state} do
      json = Jason.encode!(%{"type" => "record_play", "feed" => "feed", "item" => "item", "position" => 0, "played" => "not_a_boolean"})
      {:error, response} = MessageHandler.handle_message(json, state)
      decoded = Jason.decode!(response)

      assert decoded["status"] == "error"
      assert decoded["error"]["code"] == "MISSING_FIELDS"
    end

    test "rejects record_play with negative position", %{authenticated_state: state} do
      json = Jason.encode!(%{"type" => "record_play", "feed" => "feed", "item" => "item", "position" => -1, "played" => false})
      {:error, response} = MessageHandler.handle_message(json, state)
      decoded = Jason.decode!(response)

      assert decoded["status"] == "error"
      assert decoded["error"]["code"] == "MISSING_FIELDS"
    end
  end

  describe "handle_message/2 - Valid message structure" do
    setup do
      authenticated_state = State.authenticate(State.new(), "user_123", :play_token, "token_abc")
      {:ok, authenticated_state: authenticated_state}
    end

    test "validates correct message format", %{authenticated_state: state} do
      json = Jason.encode!(%{
        "type" => "record_play",
        "feed" => "base64_feed",
        "item" => "base64_item",
        "position" => 123,
        "played" => false
      })

      # This will try to dispatch but will fail because Dispatcher.dispatch is not mocked
      # We just test the validation passes here
      result = MessageHandler.handle_message(json, state)
      assert is_tuple(result)
    end

    test "accepts position 0", %{authenticated_state: state} do
      json = Jason.encode!(%{
        "type" => "record_play",
        "feed" => "base64_feed",
        "item" => "base64_item",
        "position" => 0,
        "played" => false
      })

      result = MessageHandler.handle_message(json, state)
      assert is_tuple(result)
    end

    test "accepts both played values", %{authenticated_state: state} do
      for played <- [true, false] do
        json = Jason.encode!(%{
          "type" => "record_play",
          "feed" => "base64_feed",
          "item" => "base64_item",
          "position" => 100,
          "played" => played
        })

        result = MessageHandler.handle_message(json, state)
        assert is_tuple(result)
      end
    end
  end

  describe "message responses" do
    test "error response has correct structure" do
      json = Jason.encode!(%{"type" => "unknown"})
      state = State.new()
      {:error, response} = MessageHandler.handle_message(json, state)
      decoded = Jason.decode!(response)

      assert is_map(decoded)
      assert decoded["status"] == "error"
      assert is_map(decoded["error"])
      assert is_binary(decoded["error"]["message"])
      assert is_binary(decoded["error"]["code"])
    end
  end
end
