defmodule BaladosSyncWeb.LiveWebSocket.StateTest do
  use ExUnit.Case, async: true

  alias BaladosSyncWeb.LiveWebSocket.State

  describe "new/0" do
    test "creates unauthenticated state" do
      state = State.new()

      assert state.auth_status == :unauthenticated
      assert state.user_id == nil
      assert state.token_type == nil
      assert state.token_value == nil
      assert state.message_count == 0
      assert is_struct(state.connected_at, DateTime)
      assert is_struct(state.last_activity_at, DateTime)
    end

    test "sets timestamps" do
      before = DateTime.utc_now()
      state = State.new()
      after_time = DateTime.utc_now()

      assert DateTime.compare(state.connected_at, before) != :lt
      assert DateTime.compare(state.connected_at, after_time) != :gt
      assert DateTime.compare(state.last_activity_at, before) != :lt
      assert DateTime.compare(state.last_activity_at, after_time) != :gt
    end
  end

  describe "authenticate/4" do
    test "transitions to authenticated state" do
      state = State.new()
      new_state = State.authenticate(state, "user_123", :play_token, "token_abc")

      assert new_state.auth_status == :authenticated
      assert new_state.user_id == "user_123"
      assert new_state.token_type == :play_token
      assert new_state.token_value == "token_abc"
    end

    test "supports both token types" do
      state = State.new()

      play_token_state = State.authenticate(state, "user_1", :play_token, "token_1")
      assert play_token_state.token_type == :play_token

      jwt_token_state = State.authenticate(state, "user_2", :jwt_token, "token_2")
      assert jwt_token_state.token_type == :jwt_token
    end

    test "updates last_activity_at" do
      state = State.new()
      before = DateTime.utc_now()
      new_state = State.authenticate(state, "user_123", :play_token, "token_abc")
      after_time = DateTime.utc_now()

      assert DateTime.compare(new_state.last_activity_at, before) != :lt
      assert DateTime.compare(new_state.last_activity_at, after_time) != :gt
    end

    test "preserves message_count" do
      state = %State{State.new() | message_count: 5}
      new_state = State.authenticate(state, "user_123", :play_token, "token_abc")

      assert new_state.message_count == 5
    end
  end

  describe "touch/1" do
    test "increments message count" do
      state = State.new()

      state1 = State.touch(state)
      assert state1.message_count == 1

      state2 = State.touch(state1)
      assert state2.message_count == 2
    end

    test "updates last_activity_at" do
      state = State.new()
      before = DateTime.utc_now()
      new_state = State.touch(state)
      after_time = DateTime.utc_now()

      assert DateTime.compare(new_state.last_activity_at, before) != :lt
      assert DateTime.compare(new_state.last_activity_at, after_time) != :gt
    end

    test "preserves auth state" do
      state = State.authenticate(State.new(), "user_123", :play_token, "token_abc")
      new_state = State.touch(state)

      assert new_state.auth_status == :authenticated
      assert new_state.user_id == "user_123"
      assert new_state.token_type == :play_token
      assert new_state.token_value == "token_abc"
    end
  end

  describe "authenticated?/1" do
    test "returns false for unauthenticated state" do
      state = State.new()
      refute State.authenticated?(state)
    end

    test "returns true for authenticated state" do
      state = State.authenticate(State.new(), "user_123", :play_token, "token_abc")
      assert State.authenticated?(state)
    end
  end
end
