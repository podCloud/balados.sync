defmodule BaladosSyncCore.CommandPropertiesTest do
  @moduledoc """
  Property-based tests for CQRS commands.

  These tests verify that commands maintain their invariants
  across a wide range of randomly generated inputs.
  """

  use ExUnit.Case, async: true
  use ExUnitProperties

  alias BaladosSyncCore.Generators

  describe "Subscribe command" do
    property "generated commands have valid structure" do
      check all cmd <- Generators.subscribe_command() do
        assert is_binary(cmd.user_id)
        assert is_binary(cmd.rss_source_feed)
        assert is_binary(cmd.rss_source_id)
        assert is_map(cmd.event_infos)
        assert Map.has_key?(cmd.event_infos, :device_id)
        assert Map.has_key?(cmd.event_infos, :device_name)
      end
    end

    property "user_id is a valid UUID format" do
      check all cmd <- Generators.subscribe_command() do
        # UUID format: 8-4-4-4-12 hex chars
        assert String.match?(cmd.user_id, ~r/^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$/)
      end
    end

    property "rss_source_feed is valid Base64" do
      check all cmd <- Generators.subscribe_command() do
        assert {:ok, decoded} = Base.decode64(cmd.rss_source_feed)
        assert String.starts_with?(decoded, "http")
      end
    end

    property "rss_source_id is lowercase alphanumeric" do
      check all cmd <- Generators.subscribe_command() do
        assert cmd.rss_source_id == String.downcase(cmd.rss_source_id)
        assert String.match?(cmd.rss_source_id, ~r/^[a-z0-9]+$/)
      end
    end
  end

  describe "Unsubscribe command" do
    property "generated commands have valid structure" do
      check all cmd <- Generators.unsubscribe_command() do
        assert is_binary(cmd.user_id)
        assert is_binary(cmd.rss_source_feed)
        assert is_map(cmd.event_infos)
      end
    end

    property "user_id matches UUID format" do
      check all cmd <- Generators.unsubscribe_command() do
        assert String.match?(cmd.user_id, ~r/^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$/)
      end
    end
  end

  describe "RecordPlay command" do
    property "generated commands have valid structure" do
      check all cmd <- Generators.record_play_command() do
        assert is_binary(cmd.user_id)
        assert is_binary(cmd.rss_source_feed)
        assert is_binary(cmd.rss_source_item)
        assert is_integer(cmd.position)
        assert is_boolean(cmd.played)
        assert is_map(cmd.event_infos)
      end
    end

    property "position is non-negative" do
      check all cmd <- Generators.record_play_command() do
        assert cmd.position >= 0
      end
    end

    property "position is within reasonable bounds (max 2 hours)" do
      check all cmd <- Generators.record_play_command() do
        assert cmd.position <= 7200
      end
    end

    property "rss_source_item decodes to valid item format" do
      check all cmd <- Generators.record_play_command() do
        {:ok, decoded} = Base.decode64(cmd.rss_source_item)
        # Format: guid,url
        assert String.contains?(decoded, ",")
        assert String.contains?(decoded, "http")
      end
    end
  end

  describe "ChangePrivacy command" do
    property "generated commands have valid structure" do
      check all cmd <- Generators.change_privacy_command() do
        assert is_binary(cmd.user_id)
        assert is_binary(cmd.rss_source_feed)
        assert cmd.rss_source_item == nil or is_binary(cmd.rss_source_item)
        assert cmd.privacy in ["public", "private", "anonymous"]
        assert is_map(cmd.event_infos)
      end
    end

    property "privacy is always one of the valid values" do
      check all cmd <- Generators.change_privacy_command() do
        assert cmd.privacy in ["public", "private", "anonymous"]
      end
    end
  end

  describe "Base generators" do
    property "uuid generator produces valid UUIDs" do
      check all id <- Generators.uuid() do
        assert String.length(id) == 36
        assert String.match?(id, ~r/^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$/)
      end
    end

    property "email generator produces valid emails" do
      check all email <- Generators.email() do
        assert String.contains?(email, "@")
        assert String.match?(email, ~r/^[a-z0-9]+@[a-z]+\.[a-z]+$/)
      end
    end

    property "rss_feed generator produces valid Base64 URLs" do
      check all feed <- Generators.rss_feed() do
        {:ok, decoded} = Base.decode64(feed)
        assert String.match?(decoded, ~r/^https?:\/\//)
        assert String.ends_with?(decoded, "/feed.xml")
      end
    end

    property "rss_item generator produces valid Base64 items" do
      check all item <- Generators.rss_item() do
        {:ok, decoded} = Base.decode64(item)
        [_guid, url] = String.split(decoded, ",")
        assert String.starts_with?(url, "https://")
        assert String.ends_with?(url, ".mp3")
      end
    end

    property "position is always within bounds" do
      check all pos <- Generators.position() do
        assert pos >= 0
        assert pos <= 7200
      end
    end

    property "privacy is always valid" do
      check all priv <- Generators.privacy() do
        assert priv in ["public", "private", "anonymous"]
      end
    end

    property "timestamp produces valid ISO 8601 strings" do
      check all ts <- Generators.timestamp() do
        assert String.match?(ts, ~r/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$/)
      end
    end
  end

  describe "Invalid data generators" do
    property "invalid_rss_feed generates non-URL strings" do
      check all feed <- Generators.invalid_rss_feed() do
        case Base.decode64(feed) do
          {:ok, decoded} ->
            # If it decodes, it should not be a valid URL
            refute String.starts_with?(decoded, "http://") and String.contains?(decoded, "/feed")
            refute String.starts_with?(decoded, "https://") and String.contains?(decoded, "/feed")

          :error ->
            # If it doesn't decode, that's also invalid
            assert true
        end
      end
    end

    property "invalid_privacy is never a valid privacy value" do
      check all priv <- Generators.invalid_privacy() do
        refute priv in ["public", "private", "anonymous"]
      end
    end

    property "invalid_position is always out of bounds" do
      check all pos <- Generators.invalid_position() do
        assert pos < 0 or pos > 100_000
      end
    end
  end
end
