defmodule BaladosSyncWeb.EnrichedPodcastsTest do
  @moduledoc """
  Tests for the EnrichedPodcasts context module.
  """

  use BaladosSyncProjections.DataCase

  alias BaladosSyncWeb.EnrichedPodcasts

  @valid_attrs %{
    feed_url: "https://example.com/feed.xml",
    slug: "my-podcast",
    background_color: "#FF5733",
    links: [%{"type" => "twitter", "url" => "https://twitter.com/podcast"}],
    created_by_user_id: nil
  }

  defp create_enriched_podcast(attrs \\ %{}) do
    user_id = attrs[:created_by_user_id] || Ecto.UUID.generate()

    {:ok, enriched_podcast} =
      EnrichedPodcasts.create_enriched_podcast(
        Map.merge(@valid_attrs, %{created_by_user_id: user_id})
        |> Map.merge(attrs)
      )

    enriched_podcast
  end

  describe "list_enriched_podcasts/0" do
    test "returns all enriched podcasts" do
      _ep1 = create_enriched_podcast(%{slug: "podcast-one"})
      _ep2 = create_enriched_podcast(%{slug: "podcast-two", feed_url: "https://other.com/feed.xml"})

      podcasts = EnrichedPodcasts.list_enriched_podcasts()

      assert length(podcasts) == 2
      slugs = Enum.map(podcasts, & &1.slug)
      assert "podcast-one" in slugs
      assert "podcast-two" in slugs
    end

    test "returns empty list when no enriched podcasts exist" do
      assert EnrichedPodcasts.list_enriched_podcasts() == []
    end
  end

  describe "get/1" do
    test "returns enriched podcast by id" do
      enriched_podcast = create_enriched_podcast()

      result = EnrichedPodcasts.get(enriched_podcast.id)

      assert result.id == enriched_podcast.id
    end

    test "returns nil for non-existent id" do
      assert EnrichedPodcasts.get(Ecto.UUID.generate()) == nil
    end
  end

  describe "get_by_slug/1" do
    test "returns enriched podcast by slug" do
      enriched_podcast = create_enriched_podcast(%{slug: "my-unique-slug"})

      result = EnrichedPodcasts.get_by_slug("my-unique-slug")

      assert result.id == enriched_podcast.id
    end

    test "returns nil for non-existent slug" do
      assert EnrichedPodcasts.get_by_slug("non-existent") == nil
    end
  end

  describe "get_by_feed_url/1" do
    test "returns enriched podcast by feed URL" do
      enriched_podcast = create_enriched_podcast(%{feed_url: "https://unique.com/feed.xml"})

      result = EnrichedPodcasts.get_by_feed_url("https://unique.com/feed.xml")

      assert result.id == enriched_podcast.id
    end

    test "returns nil for non-existent feed URL" do
      assert EnrichedPodcasts.get_by_feed_url("https://nonexistent.com/feed.xml") == nil
    end
  end

  describe "get_by_encoded_feed/1" do
    test "returns enriched podcast by base64-encoded feed URL" do
      feed_url = "https://encoded.com/feed.xml"
      enriched_podcast = create_enriched_podcast(%{feed_url: feed_url, slug: "encoded-test"})
      encoded = Base.url_encode64(feed_url, padding: false)

      result = EnrichedPodcasts.get_by_encoded_feed(encoded)

      assert result.id == enriched_podcast.id
    end

    test "returns nil for invalid base64" do
      assert EnrichedPodcasts.get_by_encoded_feed("!!!invalid!!!") == nil
    end
  end

  describe "create_enriched_podcast/1" do
    test "creates enriched podcast with valid attrs" do
      attrs = %{
        feed_url: "https://new.com/feed.xml",
        slug: "new-podcast",
        created_by_user_id: Ecto.UUID.generate()
      }

      {:ok, enriched_podcast} = EnrichedPodcasts.create_enriched_podcast(attrs)

      assert enriched_podcast.slug == "new-podcast"
      assert enriched_podcast.feed_url == "https://new.com/feed.xml"
    end

    test "returns error for invalid attrs" do
      {:error, changeset} = EnrichedPodcasts.create_enriched_podcast(%{})

      refute changeset.valid?
    end

    test "enforces unique slug" do
      create_enriched_podcast(%{slug: "unique-slug"})

      {:error, changeset} = EnrichedPodcasts.create_enriched_podcast(%{
        feed_url: "https://other.com/feed.xml",
        slug: "unique-slug",
        created_by_user_id: Ecto.UUID.generate()
      })

      assert "has already been taken" in errors_on(changeset).slug
    end

    test "enforces unique feed_url" do
      create_enriched_podcast(%{feed_url: "https://unique-feed.com/feed.xml"})

      {:error, changeset} = EnrichedPodcasts.create_enriched_podcast(%{
        feed_url: "https://unique-feed.com/feed.xml",
        slug: "other-slug",
        created_by_user_id: Ecto.UUID.generate()
      })

      assert "has already been taken" in errors_on(changeset).feed_url
    end
  end

  describe "update_enriched_podcast/2" do
    test "updates enriched podcast with valid attrs" do
      enriched_podcast = create_enriched_podcast()

      {:ok, updated} = EnrichedPodcasts.update_enriched_podcast(enriched_podcast, %{
        slug: "updated-slug",
        background_color: "#000000"
      })

      assert updated.slug == "updated-slug"
      assert updated.background_color == "#000000"
    end

    test "returns error for invalid attrs" do
      enriched_podcast = create_enriched_podcast()

      {:error, changeset} = EnrichedPodcasts.update_enriched_podcast(enriched_podcast, %{
        slug: "ab"  # too short
      })

      refute changeset.valid?
    end
  end

  describe "delete_enriched_podcast/1" do
    test "deletes enriched podcast" do
      enriched_podcast = create_enriched_podcast()

      {:ok, deleted} = EnrichedPodcasts.delete_enriched_podcast(enriched_podcast)

      assert deleted.id == enriched_podcast.id
      assert EnrichedPodcasts.get(enriched_podcast.id) == nil
    end
  end

  describe "slug_available?/1" do
    test "returns true for available slug" do
      assert EnrichedPodcasts.slug_available?("available-slug")
    end

    test "returns false for taken slug" do
      create_enriched_podcast(%{slug: "taken-slug"})

      refute EnrichedPodcasts.slug_available?("taken-slug")
    end
  end

  describe "resolve_slug_or_encoded/1" do
    test "resolves by slug" do
      enriched_podcast = create_enriched_podcast(%{slug: "resolve-test"})

      {:slug, feed_url, enrichment} = EnrichedPodcasts.resolve_slug_or_encoded("resolve-test")

      assert feed_url == enriched_podcast.feed_url
      assert enrichment.id == enriched_podcast.id
    end

    test "resolves by encoded feed URL" do
      feed_url = "https://resolve.com/feed.xml"
      enriched_podcast = create_enriched_podcast(%{feed_url: feed_url, slug: "resolve-encoded"})
      encoded = Base.url_encode64(feed_url, padding: false)

      {:encoded, result_feed_url, enrichment} = EnrichedPodcasts.resolve_slug_or_encoded(encoded)

      assert result_feed_url == feed_url
      assert enrichment.id == enriched_podcast.id
    end

    test "resolves encoded feed without enrichment" do
      feed_url = "https://no-enrichment.com/feed.xml"
      encoded = Base.url_encode64(feed_url, padding: false)

      {:encoded, result_feed_url, enrichment} = EnrichedPodcasts.resolve_slug_or_encoded(encoded)

      assert result_feed_url == feed_url
      assert enrichment == nil
    end

    test "returns error for invalid input" do
      {:error, :invalid} = EnrichedPodcasts.resolve_slug_or_encoded("!!!invalid!!!")
    end
  end
end
