defmodule BaladosSyncCore.Generators do
  @moduledoc """
  StreamData generators for property-based testing.

  Provides generators for common types used throughout the Balados Sync domain:
  UUIDs, Base64-encoded URLs, commands, and events.

  ## Usage

      use ExUnitProperties

      property "subscribe accepts valid feeds" do
        check all user_id <- Generators.uuid(),
                  feed <- Generators.rss_feed() do
          assert is_binary(user_id)
          assert is_binary(feed)
        end
      end
  """

  use ExUnitProperties

  # ============================================================================
  # Base Generators
  # ============================================================================

  @doc """
  Generates a valid UUID v4 string.
  """
  def uuid do
    StreamData.map(
      StreamData.fixed_list([
        StreamData.binary(length: 4),
        StreamData.binary(length: 2),
        StreamData.binary(length: 2),
        StreamData.binary(length: 2),
        StreamData.binary(length: 6)
      ]),
      fn [a, b, c, d, e] ->
        # Format as UUID v4
        [Base.encode16(a, case: :lower),
         Base.encode16(b, case: :lower),
         Base.encode16(c, case: :lower),
         Base.encode16(d, case: :lower),
         Base.encode16(e, case: :lower)]
        |> Enum.join("-")
      end
    )
  end

  @doc """
  Generates a valid email address.
  """
  def email do
    StreamData.map(
      StreamData.tuple({
        StreamData.string(:alphanumeric, min_length: 1, max_length: 20),
        StreamData.member_of(["gmail.com", "example.com", "test.org", "mail.net"])
      }),
      fn {local, domain} -> "#{String.downcase(local)}@#{domain}" end
    )
  end

  @doc """
  Generates a valid RSS feed URL (Base64-encoded).
  """
  def rss_feed do
    StreamData.map(
      StreamData.tuple({
        StreamData.member_of(["https", "http"]),
        StreamData.string(:alphanumeric, min_length: 3, max_length: 20),
        StreamData.member_of([".com", ".org", ".net", ".io"]),
        StreamData.string(:alphanumeric, min_length: 1, max_length: 10)
      }),
      fn {scheme, domain, tld, path} ->
        url = "#{scheme}://#{String.downcase(domain)}#{tld}/#{String.downcase(path)}/feed.xml"
        Base.encode64(url)
      end
    )
  end

  @doc """
  Generates a valid RSS item identifier (Base64-encoded).
  """
  def rss_item do
    StreamData.map(
      StreamData.tuple({
        StreamData.string(:alphanumeric, min_length: 5, max_length: 20),
        StreamData.string(:alphanumeric, min_length: 3, max_length: 15)
      }),
      fn {guid, filename} ->
        item = "#{guid},https://example.com/#{String.downcase(filename)}.mp3"
        Base.encode64(item)
      end
    )
  end

  @doc """
  Generates a valid podcast ID.
  """
  def podcast_id do
    StreamData.map(
      StreamData.string(:alphanumeric, min_length: 5, max_length: 30),
      &String.downcase/1
    )
  end

  @doc """
  Generates a valid device info map.
  """
  def device_info do
    StreamData.fixed_map(%{
      device_id: StreamData.string(:alphanumeric, min_length: 5, max_length: 20),
      device_name: StreamData.member_of(["iPhone", "Android", "Web", "Desktop", "API"])
    })
  end

  @doc """
  Generates a valid privacy setting (as string for commands).
  """
  def privacy do
    StreamData.member_of(["public", "private", "anonymous"])
  end

  @doc """
  Generates a valid privacy setting (as atom for events).
  """
  def privacy_atom do
    StreamData.member_of([:public, :private, :anonymous])
  end

  @doc """
  Generates a valid playback position (0 to 7200 seconds = 2 hours).
  """
  def position do
    StreamData.integer(0..7200)
  end

  @doc """
  Generates a valid timestamp string.
  """
  def timestamp do
    StreamData.map(
      StreamData.tuple({
        StreamData.integer(2020..2025),
        StreamData.integer(1..12),
        StreamData.integer(1..28),
        StreamData.integer(0..23),
        StreamData.integer(0..59),
        StreamData.integer(0..59)
      }),
      fn {year, month, day, hour, min, sec} ->
        month_str = String.pad_leading(to_string(month), 2, "0")
        day_str = String.pad_leading(to_string(day), 2, "0")
        hour_str = String.pad_leading(to_string(hour), 2, "0")
        min_str = String.pad_leading(to_string(min), 2, "0")
        sec_str = String.pad_leading(to_string(sec), 2, "0")
        "#{year}-#{month_str}-#{day_str}T#{hour_str}:#{min_str}:#{sec_str}Z"
      end
    )
  end

  # ============================================================================
  # Command Generators
  # ============================================================================

  @doc """
  Generates a valid Subscribe command.
  """
  def subscribe_command do
    StreamData.fixed_map(%{
      __struct__: StreamData.constant(BaladosSyncCore.Commands.Subscribe),
      user_id: uuid(),
      rss_source_feed: rss_feed(),
      rss_source_id: podcast_id(),
      subscribed_at: StreamData.one_of([StreamData.constant(nil), StreamData.constant(DateTime.utc_now())]),
      event_infos: device_info()
    })
  end

  @doc """
  Generates a valid Unsubscribe command.
  """
  def unsubscribe_command do
    StreamData.fixed_map(%{
      __struct__: StreamData.constant(BaladosSyncCore.Commands.Unsubscribe),
      user_id: uuid(),
      rss_source_feed: rss_feed(),
      unsubscribed_at: StreamData.one_of([StreamData.constant(nil), StreamData.constant(DateTime.utc_now())]),
      event_infos: device_info()
    })
  end

  @doc """
  Generates a valid RecordPlay command.
  """
  def record_play_command do
    StreamData.fixed_map(%{
      __struct__: StreamData.constant(BaladosSyncCore.Commands.RecordPlay),
      user_id: uuid(),
      rss_source_feed: rss_feed(),
      rss_source_item: rss_item(),
      position: position(),
      played: StreamData.boolean(),
      event_infos: device_info()
    })
  end

  @doc """
  Generates a valid ChangePrivacy command.
  """
  def change_privacy_command do
    StreamData.fixed_map(%{
      __struct__: StreamData.constant(BaladosSyncCore.Commands.ChangePrivacy),
      user_id: uuid(),
      rss_source_feed: rss_feed(),
      rss_source_item: StreamData.one_of([rss_item(), StreamData.constant(nil)]),
      privacy: privacy(),
      event_infos: device_info()
    })
  end

  # ============================================================================
  # Event Generators
  # ============================================================================

  @doc """
  Generates a valid UserSubscribed event.
  """
  def user_subscribed_event do
    StreamData.fixed_map(%{
      __struct__: StreamData.constant(BaladosSyncCore.Events.UserSubscribed),
      user_id: uuid(),
      rss_source_feed: rss_feed(),
      rss_source_id: podcast_id(),
      subscribed_at: timestamp(),
      event_infos: device_info()
    })
  end

  @doc """
  Generates a valid PlayRecorded event.
  """
  def play_recorded_event do
    StreamData.fixed_map(%{
      __struct__: StreamData.constant(BaladosSyncCore.Events.PlayRecorded),
      user_id: uuid(),
      rss_source_feed: rss_feed(),
      rss_source_item: rss_item(),
      position: position(),
      played: StreamData.boolean(),
      timestamp: timestamp(),
      event_infos: device_info()
    })
  end

  @doc """
  Generates a valid PrivacyChanged event.
  """
  def privacy_changed_event do
    StreamData.fixed_map(%{
      __struct__: StreamData.constant(BaladosSyncCore.Events.PrivacyChanged),
      user_id: uuid(),
      rss_source_feed: rss_feed(),
      rss_source_item: StreamData.one_of([rss_item(), StreamData.constant(nil)]),
      privacy: privacy_atom(),
      timestamp: timestamp(),
      event_infos: device_info()
    })
  end

  # ============================================================================
  # Invalid Data Generators (for testing rejection)
  # ============================================================================

  @doc """
  Generates an invalid RSS feed URL (not Base64, or invalid URL format).
  """
  def invalid_rss_feed do
    StreamData.one_of([
      # Not Base64
      StreamData.string(:alphanumeric, min_length: 10, max_length: 30),
      # Empty string
      StreamData.constant(""),
      # Just whitespace
      StreamData.constant("   "),
      # Invalid Base64 of non-URL
      StreamData.map(
        StreamData.string(:alphanumeric, min_length: 5, max_length: 20),
        &Base.encode64/1
      )
    ])
  end

  @doc """
  Generates an invalid privacy value.
  """
  def invalid_privacy do
    StreamData.one_of([
      StreamData.constant(""),
      StreamData.constant("invalid_value"),
      StreamData.constant("PUBLIC"),  # wrong case
      StreamData.constant("Private"), # wrong case
      StreamData.constant(nil)
    ])
  end

  @doc """
  Generates an invalid position (negative or too large).
  """
  def invalid_position do
    StreamData.one_of([
      StreamData.integer(-1000..-1),
      StreamData.integer(1_000_000..10_000_000)
    ])
  end
end
