defmodule BaladosSyncCore.UrlValidatorTest do
  use ExUnit.Case, async: true

  alias BaladosSyncCore.UrlValidator

  describe "validate_rss_url/1" do
    test "accepts valid HTTP URLs" do
      assert :ok = UrlValidator.validate_rss_url("http://example.com/feed.xml")
      assert :ok = UrlValidator.validate_rss_url("http://podcast.example.org/rss")
    end

    test "accepts valid HTTPS URLs" do
      assert :ok = UrlValidator.validate_rss_url("https://example.com/feed.xml")
      assert :ok = UrlValidator.validate_rss_url("https://feeds.example.com/podcast")
    end

    test "rejects non-HTTP schemes" do
      assert {:error, :invalid_scheme} = UrlValidator.validate_rss_url("ftp://example.com/feed.xml")
      # file:// URLs have empty host, which fails before scheme check
      assert {:error, :empty_host} = UrlValidator.validate_rss_url("file:///etc/passwd")
      # javascript: URLs have no host at all
      assert {:error, :missing_host} = UrlValidator.validate_rss_url("javascript:alert(1)")
    end

    test "rejects URLs without scheme" do
      assert {:error, :missing_scheme} = UrlValidator.validate_rss_url("example.com/feed.xml")
    end

    test "rejects URLs without host" do
      # http:/// has an empty host, not a missing host
      assert {:error, :empty_host} = UrlValidator.validate_rss_url("http:///path")
    end

    test "rejects non-string input" do
      assert {:error, :invalid_url} = UrlValidator.validate_rss_url(nil)
      assert {:error, :invalid_url} = UrlValidator.validate_rss_url(123)
      assert {:error, :invalid_url} = UrlValidator.validate_rss_url(%{})
    end

    # Loopback/localhost blocking
    test "blocks localhost hostname" do
      assert {:error, :localhost_blocked} = UrlValidator.validate_rss_url("http://localhost/feed")
      assert {:error, :localhost_blocked} = UrlValidator.validate_rss_url("https://LOCALHOST/feed")
    end

    test "blocks loopback IPv4 addresses (127.x.x.x)" do
      assert {:error, :loopback_blocked} = UrlValidator.validate_rss_url("http://127.0.0.1/feed")
      assert {:error, :loopback_blocked} = UrlValidator.validate_rss_url("http://127.1.2.3/feed")
      assert {:error, :loopback_blocked} = UrlValidator.validate_rss_url("http://127.255.255.255/feed")
    end

    test "blocks IPv6 loopback (::1)" do
      assert {:error, :loopback_blocked} = UrlValidator.validate_rss_url("http://[::1]/feed")
    end

    # Private IP range blocking
    test "blocks 10.x.x.x private network" do
      assert {:error, :private_ip_blocked} = UrlValidator.validate_rss_url("http://10.0.0.1/feed")
      assert {:error, :private_ip_blocked} = UrlValidator.validate_rss_url("http://10.255.255.255/feed")
    end

    test "blocks 172.16-31.x.x private network" do
      assert {:error, :private_ip_blocked} = UrlValidator.validate_rss_url("http://172.16.0.1/feed")
      assert {:error, :private_ip_blocked} = UrlValidator.validate_rss_url("http://172.31.255.255/feed")

      # 172.15.x.x and 172.32.x.x should be allowed (not in private range)
      assert :ok = UrlValidator.validate_rss_url("http://172.15.0.1/feed")
      assert :ok = UrlValidator.validate_rss_url("http://172.32.0.1/feed")
    end

    test "blocks 192.168.x.x private network" do
      assert {:error, :private_ip_blocked} = UrlValidator.validate_rss_url("http://192.168.0.1/feed")
      assert {:error, :private_ip_blocked} = UrlValidator.validate_rss_url("http://192.168.255.255/feed")
    end

    # Link-local / cloud metadata blocking
    test "blocks link-local addresses (169.254.x.x) - cloud metadata endpoints" do
      assert {:error, :link_local_blocked} = UrlValidator.validate_rss_url("http://169.254.169.254/feed")
      assert {:error, :link_local_blocked} = UrlValidator.validate_rss_url("http://169.254.0.1/feed")
    end

    test "blocks cloud metadata hostname patterns" do
      assert {:error, :cloud_metadata_blocked} =
               UrlValidator.validate_rss_url("http://metadata.google.internal/feed")
    end

    # Internal/local domain blocking
    test "blocks .internal domains" do
      assert {:error, :internal_domain_blocked} =
               UrlValidator.validate_rss_url("http://server.internal/feed")
    end

    test "blocks .local domains" do
      assert {:error, :local_domain_blocked} =
               UrlValidator.validate_rss_url("http://myserver.local/feed")
    end

    # Multicast blocking
    test "blocks multicast IPv4 addresses (224-239.x.x.x)" do
      assert {:error, :multicast_blocked} = UrlValidator.validate_rss_url("http://224.0.0.1/feed")
      assert {:error, :multicast_blocked} = UrlValidator.validate_rss_url("http://239.255.255.255/feed")
    end

    # Edge cases
    test "accepts public IP addresses" do
      assert :ok = UrlValidator.validate_rss_url("http://8.8.8.8/feed")
      assert :ok = UrlValidator.validate_rss_url("http://1.2.3.4/feed")
    end

    test "accepts standard domain names" do
      assert :ok = UrlValidator.validate_rss_url("https://feeds.megaphone.fm/podcast")
      assert :ok = UrlValidator.validate_rss_url("https://anchor.fm/s/12345/podcast/rss")
    end

    test "handles URLs with ports" do
      assert :ok = UrlValidator.validate_rss_url("http://example.com:8080/feed")
      assert {:error, :private_ip_blocked} = UrlValidator.validate_rss_url("http://192.168.1.1:8080/feed")
    end

    test "handles URLs with query strings" do
      assert :ok = UrlValidator.validate_rss_url("https://example.com/feed?token=abc")
      assert {:error, :loopback_blocked} =
               UrlValidator.validate_rss_url("http://127.0.0.1/feed?token=abc")
    end

    test "handles URLs with fragments" do
      assert :ok = UrlValidator.validate_rss_url("https://example.com/feed#section")
    end

    test "handles URLs with authentication" do
      assert :ok = UrlValidator.validate_rss_url("https://user:pass@example.com/feed")
    end
  end

  describe "validate_rss_url!/1" do
    test "returns URL when valid" do
      url = "https://example.com/feed.xml"
      assert ^url = UrlValidator.validate_rss_url!(url)
    end

    test "raises ArgumentError when invalid" do
      assert_raise ArgumentError, ~r/Invalid URL/, fn ->
        UrlValidator.validate_rss_url!("http://127.0.0.1/feed")
      end
    end
  end
end
