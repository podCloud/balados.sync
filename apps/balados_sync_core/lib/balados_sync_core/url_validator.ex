defmodule BaladosSyncCore.UrlValidator do
  @moduledoc """
  URL validation module for preventing SSRF (Server-Side Request Forgery) attacks.

  This module validates URLs before they are used for HTTP requests to prevent
  attackers from using the server to access internal resources.

  ## Blocked Resources

  - Non-HTTP(S) schemes, missing or empty hosts
  - Loopback (127.0.0.0/8, ::1) and unspecified addresses (0.0.0.0/8, ::)
  - Private ranges (10/8, 172.16/12, 192.168/16, fc00::/7)
  - Link-local (169.254/16, fe80::/10), including cloud metadata endpoints
  - Multicast (224/4, ff00::/8) and special-use ranges (100.64/10,
    192.0.0/24, 198.18/15, 240/4, fec0::/10, 64:ff9b:1::/48)
  - IPv6 forms embedding a blocked IPv4 address: mapped `::ffff:a.b.c.d`,
    SIIT `::ffff:0:a.b.c.d`, compatible `::a.b.c.d`, NAT64 `64:ff9b::/96`,
    6to4 `2002::/16`
  - Host names: `localhost`, `*.localhost`, `localhost.localdomain`,
    `*.internal`, `*.local`, cloud metadata names (case-insensitive, trailing
    dot ignored)

  Host names are **not resolved**: a name whose DNS (or `/etc/hosts`) points
  to a blocked address passes this check (issue #297). Callers fetching
  third-party URLs should go through `BaladosSyncCore.SafeHttp`, which also
  re-validates every redirect target.

  ## Usage

      case UrlValidator.validate_rss_url(url) do
        :ok -> # Safe to fetch
        {:error, reason} -> # Block the request
      end
  """

  require Logger

  @doc """
  Validates a URL for safe RSS fetching.

  Returns `:ok` if the URL is safe, or `{:error, reason}` if it should be blocked.
  """
  @spec validate_rss_url(String.t()) :: :ok | {:error, atom()}
  def validate_rss_url(url) when is_binary(url) do
    with {:ok, parsed} <- parse_url(url),
         :ok <- validate_scheme(parsed),
         :ok <- validate_host(parsed.host) do
      :ok
    end
  end

  def validate_rss_url(_), do: {:error, :invalid_url}

  @doc """
  Validates a URL and returns the validated URL or raises an error.
  """
  @spec validate_rss_url!(String.t()) :: String.t()
  def validate_rss_url!(url) do
    case validate_rss_url(url) do
      :ok -> url
      {:error, reason} -> raise ArgumentError, "Invalid URL: #{reason}"
    end
  end

  # Parse the URL
  defp parse_url(url) do
    case URI.parse(url) do
      %URI{scheme: nil} -> {:error, :missing_scheme}
      %URI{host: nil} -> {:error, :missing_host}
      %URI{host: ""} -> {:error, :empty_host}
      parsed -> {:ok, parsed}
    end
  end

  # Validate the scheme (only http and https allowed)
  defp validate_scheme(%URI{scheme: scheme}) when scheme in ["http", "https"], do: :ok

  defp validate_scheme(%URI{scheme: scheme}) do
    Logger.warning("[UrlValidator] Blocked scheme: #{scheme}")
    {:error, :invalid_scheme}
  end

  # Validate the host. A trailing dot ("localhost.") names the same host and
  # is stripped first; IPv6 forms that embed an IPv4 address (mapped,
  # compatible, NAT64, 6to4) are checked against the IPv4 rules too.
  defp validate_host(host) do
    host = host |> String.trim_trailing(".") |> String.downcase()

    case parse_ip(host) do
      {:ok, ip} ->
        with :ok <- validate_ip_address(ip) do
          case embedded_ipv4(ip) do
            nil -> :ok
            ipv4 -> validate_ip_address(ipv4)
          end
        end

      :not_ip ->
        # It's a hostname - check for obvious bad patterns
        with :ok <- check_hostname_patterns(host) do
          # Optionally resolve and validate
          # For now, we accept valid hostnames that pass pattern checks
          :ok
        end
    end
  end

  # Try to parse as IP address
  defp parse_ip(host) do
    case :inet.parse_address(to_charlist(host)) do
      {:ok, ip} -> {:ok, ip}
      {:error, _} -> :not_ip
    end
  end

  # Check for blocked hostname patterns
  defp check_hostname_patterns(host) do
    host_lower = String.downcase(host)

    cond do
      # Block localhost variations (RFC 6761: *.localhost is loopback too)
      host_lower in ["localhost", "localhost.localdomain"] or
          String.ends_with?(host_lower, ".localhost") ->
        Logger.warning("[UrlValidator] Blocked localhost: #{host}")
        {:error, :localhost_blocked}

      # Block cloud metadata endpoints
      String.contains?(host_lower, "metadata") and String.contains?(host_lower, "google") ->
        Logger.warning("[UrlValidator] Blocked cloud metadata: #{host}")
        {:error, :cloud_metadata_blocked}

      String.contains?(host_lower, "169.254.169.254") ->
        Logger.warning("[UrlValidator] Blocked cloud metadata IP: #{host}")
        {:error, :cloud_metadata_blocked}

      # Block internal domains (common patterns)
      String.ends_with?(host_lower, ".internal") ->
        Logger.warning("[UrlValidator] Blocked internal domain: #{host}")
        {:error, :internal_domain_blocked}

      String.ends_with?(host_lower, ".local") ->
        Logger.warning("[UrlValidator] Blocked local domain: #{host}")
        {:error, :local_domain_blocked}

      true ->
        :ok
    end
  end

  # IPv4 address embedded in an IPv6 one, or nil
  # ::ffff:a.b.c.d (IPv4-mapped)
  defp embedded_ipv4({0, 0, 0, 0, 0, 0xFFFF, hi, lo}), do: v4(hi, lo)
  # ::ffff:0:a.b.c.d (SIIT, RFC 6145)
  defp embedded_ipv4({0, 0, 0, 0, 0xFFFF, 0, hi, lo}), do: v4(hi, lo)
  # ::a.b.c.d (deprecated IPv4-compatible); :: and ::1 are handled as IPv6
  defp embedded_ipv4({0, 0, 0, 0, 0, 0, hi, lo}) when hi != 0 or lo > 1, do: v4(hi, lo)
  # 64:ff9b::a.b.c.d (NAT64 well-known prefix)
  defp embedded_ipv4({0x64, 0xFF9B, 0, 0, 0, 0, hi, lo}), do: v4(hi, lo)
  # 2002:aabb:ccdd::/48 (6to4)
  defp embedded_ipv4({0x2002, hi, lo, _, _, _, _, _}), do: v4(hi, lo)
  defp embedded_ipv4(_), do: nil

  defp v4(hi, lo), do: {div(hi, 256), rem(hi, 256), div(lo, 256), rem(lo, 256)}

  # Validate IP address against blocked ranges
  defp validate_ip_address(ip) do
    cond do
      is_unspecified?(ip) ->
        Logger.warning("[UrlValidator] Blocked unspecified IP: #{format_ip(ip)}")
        {:error, :unspecified_ip_blocked}

      is_reserved?(ip) ->
        Logger.warning("[UrlValidator] Blocked special-use IP: #{format_ip(ip)}")
        {:error, :reserved_ip_blocked}

      is_loopback?(ip) ->
        Logger.warning("[UrlValidator] Blocked loopback IP: #{format_ip(ip)}")
        {:error, :loopback_blocked}

      is_private?(ip) ->
        Logger.warning("[UrlValidator] Blocked private IP: #{format_ip(ip)}")
        {:error, :private_ip_blocked}

      is_link_local?(ip) ->
        Logger.warning("[UrlValidator] Blocked link-local IP: #{format_ip(ip)}")
        {:error, :link_local_blocked}

      is_multicast?(ip) ->
        Logger.warning("[UrlValidator] Blocked multicast IP: #{format_ip(ip)}")
        {:error, :multicast_blocked}

      true ->
        :ok
    end
  end

  # 0.0.0.0/8 ("this network", reaches the local host) and ::
  defp is_unspecified?({0, _, _, _}), do: true
  defp is_unspecified?({0, 0, 0, 0, 0, 0, 0, 0}), do: true
  defp is_unspecified?(_), do: false

  # Special-use IPv4 ranges that are never public feed hosts
  # 100.64.0.0/10 (carrier-grade NAT, internal on some clouds)
  defp is_reserved?({100, second, _, _}) when second >= 64 and second <= 127, do: true
  # 192.0.0.0/24 (IETF protocol assignments)
  defp is_reserved?({192, 0, 0, _}), do: true
  # 198.18.0.0/15 (benchmarking)
  defp is_reserved?({198, second, _, _}) when second in [18, 19], do: true
  # 240.0.0.0/4 (reserved) including 255.255.255.255 (broadcast)
  defp is_reserved?({first, _, _, _}) when first >= 240, do: true
  # fec0::/10 (deprecated IPv6 site-local)
  defp is_reserved?({first, _, _, _, _, _, _, _}) when first >= 0xFEC0 and first <= 0xFEFF,
    do: true

  # 64:ff9b:1::/48 (RFC 8215 local-use NAT64, prefix length not decodable)
  defp is_reserved?({0x64, 0xFF9B, 1, _, _, _, _, _}), do: true
  defp is_reserved?(_), do: false

  # IPv4 loopback: 127.0.0.0/8
  defp is_loopback?({127, _, _, _}), do: true
  # IPv6 loopback: ::1
  defp is_loopback?({0, 0, 0, 0, 0, 0, 0, 1}), do: true
  defp is_loopback?(_), do: false

  # IPv4 private ranges
  # 10.0.0.0/8
  defp is_private?({10, _, _, _}), do: true
  # 172.16.0.0/12
  defp is_private?({172, second, _, _}) when second >= 16 and second <= 31, do: true
  # 192.168.0.0/16
  defp is_private?({192, 168, _, _}), do: true
  # IPv6 private (fc00::/7)
  defp is_private?({first, _, _, _, _, _, _, _}) when first >= 0xFC00 and first <= 0xFDFF,
    do: true

  defp is_private?(_), do: false

  # IPv4 link-local: 169.254.0.0/16 (includes AWS/GCP metadata endpoints)
  defp is_link_local?({169, 254, _, _}), do: true
  # IPv6 link-local: fe80::/10
  defp is_link_local?({first, _, _, _, _, _, _, _}) when first >= 0xFE80 and first <= 0xFEBF,
    do: true

  defp is_link_local?(_), do: false

  # IPv4 multicast: 224.0.0.0/4
  defp is_multicast?({first, _, _, _}) when first >= 224 and first <= 239, do: true
  # IPv6 multicast: ff00::/8
  defp is_multicast?({first, _, _, _, _, _, _, _}) when first >= 0xFF00, do: true
  defp is_multicast?(_), do: false

  # Format IP for logging
  defp format_ip({a, b, c, d}), do: "#{a}.#{b}.#{c}.#{d}"
  defp format_ip(ip) when is_tuple(ip), do: :inet.ntoa(ip) |> to_string()
end
