defmodule BaladosSyncWeb.LiveWebSocketIntegrationTest do
  use BaladosSyncWeb.ConnCase

  alias BaladosSyncProjections.Schemas.PlayToken
  alias BaladosSyncCore.SystemRepo

  setup do
    # Create a test PlayToken for integration testing
    token = PlayToken.generate_token()
    user_id = Ecto.UUID.generate()

    play_token = %PlayToken{
      user_id: user_id,
      token: token,
      name: "Integration Test Token"
    }

    {:ok, _} = SystemRepo.insert(play_token)

    {:ok, token: token, user_id: user_id}
  end

  describe "WebSocket connection and authentication" do
    test "successfully authenticates with valid PlayToken", %{token: token, user_id: user_id} do
      # Send auth message
      auth_msg = Jason.encode!(%{"type" => "auth", "token" => token})

      # Parse response
      response =
        Jason.decode!(
          BaladosSyncWeb.LiveWebSocket.MessageHandler.handle_message(
            auth_msg,
            BaladosSyncWeb.LiveWebSocket.State.new()
          )
          |> elem(1)
        )

      assert response["status"] == "ok"
      assert response["data"]["user_id"] == user_id
    end

    test "rejects invalid PlayToken", %{} do
      invalid_token = "invalid_token_xyz"

      auth_msg = Jason.encode!(%{"type" => "auth", "token" => invalid_token})

      response =
        Jason.decode!(
          BaladosSyncWeb.LiveWebSocket.MessageHandler.handle_message(
            auth_msg,
            BaladosSyncWeb.LiveWebSocket.State.new()
          )
          |> elem(1)
        )

      assert response["status"] == "error"
      assert response["error"]["code"] == "INVALID_TOKEN"
    end

    test "prevents unauthenticated record_play messages" do
      play_msg =
        Jason.encode!(%{
          "type" => "record_play",
          "feed" => "encoded_feed",
          "item" => "encoded_item",
          "position" => 60,
          "played" => false
        })

      response =
        Jason.decode!(
          BaladosSyncWeb.LiveWebSocket.MessageHandler.handle_message(
            play_msg,
            BaladosSyncWeb.LiveWebSocket.State.new()
          )
          |> elem(1)
        )

      assert response["status"] == "error"
      assert response["error"]["code"] == "UNAUTHENTICATED"
    end

    test "validates message JSON format", %{token: _token} do
      invalid_json = "{invalid json"

      response =
        Jason.decode!(
          BaladosSyncWeb.LiveWebSocket.MessageHandler.handle_message(
            invalid_json,
            BaladosSyncWeb.LiveWebSocket.State.new()
          )
          |> elem(1)
        )

      assert response["status"] == "error"
      assert response["error"]["code"] == "INVALID_JSON"
    end

    test "rejects authentication after already authenticated", %{token: token} do
      auth_msg = Jason.encode!(%{"type" => "auth", "token" => token})

      # First authentication
      {:ok, _response, state} =
        BaladosSyncWeb.LiveWebSocket.MessageHandler.handle_message(
          auth_msg,
          BaladosSyncWeb.LiveWebSocket.State.new()
        )

      assert BaladosSyncWeb.LiveWebSocket.State.authenticated?(state)

      # Try to authenticate again
      response =
        Jason.decode!(
          BaladosSyncWeb.LiveWebSocket.MessageHandler.handle_message(
            auth_msg,
            state
          )
          |> elem(1)
        )

      assert response["status"] == "error"
      assert response["error"]["code"] == "INVALID_STATE"
    end
  end

  describe "record_play message validation" do
    setup %{token: token} do
      auth_msg = Jason.encode!(%{"type" => "auth", "token" => token})

      {:ok, _response, state} =
        BaladosSyncWeb.LiveWebSocket.MessageHandler.handle_message(
          auth_msg,
          BaladosSyncWeb.LiveWebSocket.State.new()
        )

      {:ok, authenticated_state: state}
    end

    test "accepts valid record_play message", %{authenticated_state: state} do
      play_msg =
        Jason.encode!(%{
          "type" => "record_play",
          "feed" => "base64_encoded_feed",
          "item" => "base64_encoded_item",
          "position" => 120,
          "played" => false
        })

      {:ok, response, _new_state} =
        BaladosSyncWeb.LiveWebSocket.MessageHandler.handle_message(
          play_msg,
          state
        )

      parsed = Jason.decode!(response)
      assert parsed["status"] == "ok"
    end

    test "rejects record_play without required feed field", %{authenticated_state: state} do
      play_msg =
        Jason.encode!(%{
          "type" => "record_play",
          "item" => "encoded_item",
          "position" => 60,
          "played" => false
        })

      response =
        Jason.decode!(
          BaladosSyncWeb.LiveWebSocket.MessageHandler.handle_message(
            play_msg,
            state
          )
          |> elem(1)
        )

      assert response["status"] == "error"
      assert response["error"]["code"] == "MISSING_FIELDS"
    end

    test "rejects record_play without required item field", %{authenticated_state: state} do
      play_msg =
        Jason.encode!(%{
          "type" => "record_play",
          "feed" => "encoded_feed",
          "position" => 60,
          "played" => false
        })

      response =
        Jason.decode!(
          BaladosSyncWeb.LiveWebSocket.MessageHandler.handle_message(
            play_msg,
            state
          )
          |> elem(1)
        )

      assert response["status"] == "error"
      assert response["error"]["code"] == "MISSING_FIELDS"
    end

    test "provides default position and played values", %{authenticated_state: state} do
      play_msg =
        Jason.encode!(%{
          "type" => "record_play",
          "feed" => "encoded_feed",
          "item" => "encoded_item"
        })

      {:ok, response, _new_state} =
        BaladosSyncWeb.LiveWebSocket.MessageHandler.handle_message(
          play_msg,
          state
        )

      parsed = Jason.decode!(response)
      assert parsed["status"] == "ok"
    end

    test "rejects invalid position (non-integer)", %{authenticated_state: state} do
      play_msg =
        Jason.encode!(%{
          "type" => "record_play",
          "feed" => "encoded_feed",
          "item" => "encoded_item",
          "position" => "not_a_number",
          "played" => false
        })

      response =
        Jason.decode!(
          BaladosSyncWeb.LiveWebSocket.MessageHandler.handle_message(
            play_msg,
            state
          )
          |> elem(1)
        )

      assert response["status"] == "error"
      assert response["error"]["code"] == "INVALID_POSITION"
    end

    test "rejects invalid played value (non-boolean)", %{authenticated_state: state} do
      play_msg =
        Jason.encode!(%{
          "type" => "record_play",
          "feed" => "encoded_feed",
          "item" => "encoded_item",
          "position" => 60,
          "played" => "not_a_boolean"
        })

      response =
        Jason.decode!(
          BaladosSyncWeb.LiveWebSocket.MessageHandler.handle_message(
            play_msg,
            state
          )
          |> elem(1)
        )

      assert response["status"] == "error"
      assert response["error"]["code"] == "INVALID_PLAYED"
    end
  end

  describe "state transitions" do
    setup %{token: token, user_id: user_id} do
      auth_msg = Jason.encode!(%{"type" => "auth", "token" => token})

      {:ok, _response, state} =
        BaladosSyncWeb.LiveWebSocket.MessageHandler.handle_message(
          auth_msg,
          BaladosSyncWeb.LiveWebSocket.State.new()
        )

      {:ok, authenticated_state: state, user_id: user_id}
    end

    test "state is authenticated after successful auth", %{
      authenticated_state: state,
      user_id: user_id
    } do
      assert BaladosSyncWeb.LiveWebSocket.State.authenticated?(state)
      assert state.user_id == user_id
      assert state.token_type == :play_token
    end

    test "state is touched after processing message", %{authenticated_state: state} do
      before_touch = state.last_activity_at

      play_msg =
        Jason.encode!(%{
          "type" => "record_play",
          "feed" => "encoded_feed",
          "item" => "encoded_item"
        })

      {:ok, _response, new_state} =
        BaladosSyncWeb.LiveWebSocket.MessageHandler.handle_message(
          play_msg,
          state
        )

      # Verify that state was updated
      assert new_state.last_activity_at != before_touch or
               DateTime.compare(new_state.last_activity_at, before_touch) == :gt
    end
  end

  describe "connection rate limiting" do
    alias BaladosSyncWeb.LiveWebSocket.{State, RateLimiter}

    test "allows messages within rate limit" do
      state = State.new()

      # Should allow first message
      assert {:ok, new_state} = State.check_rate_limit(state)
      assert new_state.rate_limit_bucket.tokens < state.rate_limit_bucket.tokens
    end

    test "blocks messages after exhausting bucket" do
      # Create a state with an empty bucket
      state = State.new()

      empty_bucket = %{
        tokens: 0.0,
        last_refill: System.monotonic_time(:millisecond)
      }

      state_with_empty_bucket = %{state | rate_limit_bucket: empty_bucket}

      # Should be rate limited
      assert {:error, :rate_limited, _new_state} = State.check_rate_limit(state_with_empty_bucket)
    end

    test "refills tokens over time" do
      # Create a bucket that was last refilled 200ms ago with 0 tokens
      state = State.new()

      old_bucket = %{
        tokens: 0.0,
        last_refill: System.monotonic_time(:millisecond) - 200
      }

      state_with_old_bucket = %{state | rate_limit_bucket: old_bucket}

      # Should have refilled some tokens (200ms * refill_rate/1000)
      # With default refill_rate of 10, that's 2 tokens
      assert {:ok, new_state} = State.check_rate_limit(state_with_old_bucket)
      # Tokens should be approximately 2 - 1 = 1 (refilled 2, consumed 1)
      assert new_state.rate_limit_bucket.tokens >= 0
    end

    test "rate limit bucket is per-connection" do
      # Each new state gets its own fresh bucket
      state1 = State.new()
      state2 = State.new()

      # Exhaust state1's bucket
      {final_state1, _} =
        Enum.reduce(1..RateLimiter.bucket_capacity(), {state1, 0}, fn _i, {s, count} ->
          case State.check_rate_limit(s) do
            {:ok, new_s} -> {new_s, count + 1}
            {:error, :rate_limited, new_s} -> {new_s, count}
          end
        end)

      # state1 should now be rate limited
      assert {:error, :rate_limited, _} = State.check_rate_limit(final_state1)

      # state2 should still have full capacity
      assert {:ok, _} = State.check_rate_limit(state2)
    end

    test "authenticated state preserves rate limit bucket" do
      state = State.new()

      # Consume some tokens
      {:ok, state_after_consume} = State.check_rate_limit(state)
      tokens_after_consume = state_after_consume.rate_limit_bucket.tokens

      # Authenticate the state
      authenticated_state =
        State.authenticate(
          state_after_consume,
          "user123",
          :play_token,
          "token_value"
        )

      # Rate limit bucket should be preserved
      assert authenticated_state.rate_limit_bucket.tokens == tokens_after_consume
    end
  end

  describe "error handling" do
    setup %{token: token} do
      auth_msg = Jason.encode!(%{"type" => "auth", "token" => token})

      {:ok, _response, state} =
        BaladosSyncWeb.LiveWebSocket.MessageHandler.handle_message(
          auth_msg,
          BaladosSyncWeb.LiveWebSocket.State.new()
        )

      {:ok, authenticated_state: state}
    end

    test "unknown message type returns error", %{authenticated_state: state} do
      unknown_msg = Jason.encode!(%{"type" => "unknown_type"})

      response =
        Jason.decode!(
          BaladosSyncWeb.LiveWebSocket.MessageHandler.handle_message(
            unknown_msg,
            state
          )
          |> elem(1)
        )

      assert response["status"] == "error"
      assert response["error"]["code"] == "INVALID_TYPE"
    end

    test "malformed message returns error", %{authenticated_state: state} do
      malformed_msg = Jason.encode!(%{"no_type_field" => "test"})

      response =
        Jason.decode!(
          BaladosSyncWeb.LiveWebSocket.MessageHandler.handle_message(
            malformed_msg,
            state
          )
          |> elem(1)
        )

      assert response["status"] == "error"
    end
  end
end
