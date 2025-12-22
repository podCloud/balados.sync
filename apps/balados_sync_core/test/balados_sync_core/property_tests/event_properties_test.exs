defmodule BaladosSyncCore.EventPropertiesTest do
  @moduledoc """
  Property-based tests for CQRS events.

  These tests verify that events:
  1. Maintain their structure invariants
  2. Can be serialized and deserialized (JSON roundtrip)
  3. Contain valid data for downstream projectors
  """

  use ExUnit.Case, async: true
  use ExUnitProperties

  alias BaladosSyncCore.Generators

  describe "UserSubscribed event" do
    property "generated events have valid structure" do
      check all event <- Generators.user_subscribed_event() do
        assert is_binary(event.user_id)
        assert is_binary(event.rss_source_feed)
        assert is_binary(event.rss_source_id)
        assert is_binary(event.subscribed_at)
        assert is_map(event.event_infos)
      end
    end

    property "survives JSON encode/decode roundtrip" do
      check all event <- Generators.user_subscribed_event() do
        # Convert struct to map for Jason encoding
        event_map = Map.from_struct(event)

        # Encode and decode
        encoded = Jason.encode!(event_map)
        decoded = Jason.decode!(encoded)

        # Verify key fields survive
        assert decoded["user_id"] == event.user_id
        assert decoded["rss_source_feed"] == event.rss_source_feed
        assert decoded["rss_source_id"] == event.rss_source_id
        assert decoded["subscribed_at"] == event.subscribed_at
      end
    end

    property "event_infos always contains required audit fields" do
      check all event <- Generators.user_subscribed_event() do
        assert Map.has_key?(event.event_infos, :device_id)
        assert Map.has_key?(event.event_infos, :device_name)
        assert is_binary(event.event_infos.device_id)
        assert is_binary(event.event_infos.device_name)
      end
    end
  end

  describe "PlayRecorded event" do
    property "generated events have valid structure" do
      check all event <- Generators.play_recorded_event() do
        assert is_binary(event.user_id)
        assert is_binary(event.rss_source_feed)
        assert is_binary(event.rss_source_item)
        assert is_integer(event.position)
        assert is_boolean(event.played)
        assert is_binary(event.timestamp)
        assert is_map(event.event_infos)
      end
    end

    property "survives JSON encode/decode roundtrip" do
      check all event <- Generators.play_recorded_event() do
        event_map = Map.from_struct(event)
        encoded = Jason.encode!(event_map)
        decoded = Jason.decode!(encoded)

        assert decoded["user_id"] == event.user_id
        assert decoded["rss_source_feed"] == event.rss_source_feed
        assert decoded["rss_source_item"] == event.rss_source_item
        assert decoded["position"] == event.position
        assert decoded["played"] == event.played
      end
    end

    property "position is always valid for projector" do
      check all event <- Generators.play_recorded_event() do
        # Projector expects non-negative position
        assert event.position >= 0
        # Position should be reasonable (not years of playback)
        assert event.position <= 7200
      end
    end

    property "rss_source_item is valid for decoding" do
      check all event <- Generators.play_recorded_event() do
        # Projector will decode this
        assert {:ok, _decoded} = Base.decode64(event.rss_source_item)
      end
    end
  end

  describe "PrivacyChanged event" do
    property "generated events have valid structure" do
      check all event <- Generators.privacy_changed_event() do
        assert is_binary(event.user_id)
        assert is_binary(event.rss_source_feed)
        assert event.rss_source_item == nil or is_binary(event.rss_source_item)
        assert event.privacy in [:public, :private, :anonymous]
        assert is_binary(event.timestamp)
        assert is_map(event.event_infos)
      end
    end

    property "survives JSON encode/decode roundtrip" do
      check all event <- Generators.privacy_changed_event() do
        event_map = Map.from_struct(event)
        encoded = Jason.encode!(event_map)
        decoded = Jason.decode!(encoded)

        assert decoded["user_id"] == event.user_id
        # Jason converts atoms to strings
        assert decoded["privacy"] == Atom.to_string(event.privacy)
      end
    end

    property "privacy is always a valid downstream value" do
      check all event <- Generators.privacy_changed_event() do
        # Privacy must be one of the accepted values for projectors
        assert event.privacy in [:public, :private, :anonymous]
      end
    end
  end

  describe "Event invariants across all types" do
    property "all events have user_id" do
      check all event <- StreamData.one_of([
        Generators.user_subscribed_event(),
        Generators.play_recorded_event(),
        Generators.privacy_changed_event()
      ]) do
        assert Map.has_key?(event, :user_id)
        assert is_binary(event.user_id)
        assert String.length(event.user_id) == 36
      end
    end

    property "all events have event_infos" do
      check all event <- StreamData.one_of([
        Generators.user_subscribed_event(),
        Generators.play_recorded_event(),
        Generators.privacy_changed_event()
      ]) do
        assert Map.has_key?(event, :event_infos)
        assert is_map(event.event_infos)
      end
    end

    property "all events have rss_source_feed" do
      check all event <- StreamData.one_of([
        Generators.user_subscribed_event(),
        Generators.play_recorded_event(),
        Generators.privacy_changed_event()
      ]) do
        assert Map.has_key?(event, :rss_source_feed)
        assert is_binary(event.rss_source_feed)
        assert {:ok, _} = Base.decode64(event.rss_source_feed)
      end
    end
  end

  describe "Timestamp format" do
    property "all timestamp strings are ISO 8601 format" do
      check all event <- StreamData.one_of([
        Generators.play_recorded_event(),
        Generators.privacy_changed_event()
      ]) do
        timestamp = event.timestamp
        assert String.match?(timestamp, ~r/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$/)
      end
    end

    property "subscribed_at is ISO 8601 format" do
      check all event <- Generators.user_subscribed_event() do
        assert String.match?(event.subscribed_at, ~r/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$/)
      end
    end
  end
end
