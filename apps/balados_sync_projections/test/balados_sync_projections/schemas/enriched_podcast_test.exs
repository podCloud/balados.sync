defmodule BaladosSyncProjections.Schemas.EnrichedPodcastTest do
  @moduledoc """
  Tests for the EnrichedPodcast schema validations.
  """

  use BaladosSyncProjections.DataCase

  alias BaladosSyncProjections.Schemas.EnrichedPodcast

  describe "changeset/2 validations" do
    test "valid changeset with required fields" do
      attrs = %{
        feed_url: "https://example.com/feed.xml",
        slug: "my-podcast",
        created_by_user_id: Ecto.UUID.generate()
      }

      changeset = EnrichedPodcast.changeset(%EnrichedPodcast{}, attrs)
      assert changeset.valid?
    end

    test "invalid without required fields" do
      changeset = EnrichedPodcast.changeset(%EnrichedPodcast{}, %{})
      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).feed_url
      assert "can't be blank" in errors_on(changeset).slug
      assert "can't be blank" in errors_on(changeset).created_by_user_id
    end

    test "slug must be 3-50 lowercase letters, numbers, or hyphens" do
      base_attrs = %{
        feed_url: "https://example.com/feed.xml",
        created_by_user_id: Ecto.UUID.generate()
      }

      # Valid slugs
      for slug <- ["abc", "my-podcast", "podcast-123", "a-b-c-d-e"] do
        changeset = EnrichedPodcast.changeset(%EnrichedPodcast{}, Map.put(base_attrs, :slug, slug))
        assert changeset.valid?, "Expected #{inspect(slug)} to be valid"
      end

      # Invalid slugs - too short
      changeset = EnrichedPodcast.changeset(%EnrichedPodcast{}, Map.put(base_attrs, :slug, "ab"))
      refute changeset.valid?

      # Invalid slugs - uppercase
      changeset = EnrichedPodcast.changeset(%EnrichedPodcast{}, Map.put(base_attrs, :slug, "MyPodcast"))
      refute changeset.valid?

      # Invalid slugs - special chars
      changeset = EnrichedPodcast.changeset(%EnrichedPodcast{}, Map.put(base_attrs, :slug, "my_podcast"))
      refute changeset.valid?
    end

    test "slug cannot look like base64" do
      attrs = %{
        feed_url: "https://example.com/feed.xml",
        slug: "aHR0cHM6Ly9leGFtcGxl",
        created_by_user_id: Ecto.UUID.generate()
      }

      changeset = EnrichedPodcast.changeset(%EnrichedPodcast{}, attrs)
      # This would fail because of uppercase letters (base64 pattern check)
      refute changeset.valid?
    end

    test "background_color must be valid hex format" do
      base_attrs = %{
        feed_url: "https://example.com/feed.xml",
        slug: "my-podcast",
        created_by_user_id: Ecto.UUID.generate()
      }

      # Valid colors
      for color <- ["#FF5733", "#ffffff", "#000000", "#AbCdEf"] do
        changeset = EnrichedPodcast.changeset(%EnrichedPodcast{}, Map.put(base_attrs, :background_color, color))
        assert changeset.valid?, "Expected #{inspect(color)} to be valid"
      end

      # Invalid colors
      for color <- ["FF5733", "#FFF", "red", "#GGGGGG"] do
        changeset = EnrichedPodcast.changeset(%EnrichedPodcast{}, Map.put(base_attrs, :background_color, color))
        refute changeset.valid?, "Expected #{inspect(color)} to be invalid"
      end
    end

    test "links must be valid format" do
      base_attrs = %{
        feed_url: "https://example.com/feed.xml",
        slug: "my-podcast",
        created_by_user_id: Ecto.UUID.generate()
      }

      # Valid social link
      valid_links = [
        %{"type" => "twitter", "url" => "https://twitter.com/podcast"}
      ]
      changeset = EnrichedPodcast.changeset(%EnrichedPodcast{}, Map.put(base_attrs, :links, valid_links))
      assert changeset.valid?

      # Valid custom link
      valid_custom = [
        %{"type" => "custom", "title" => "Website", "url" => "https://example.com"}
      ]
      changeset = EnrichedPodcast.changeset(%EnrichedPodcast{}, Map.put(base_attrs, :links, valid_custom))
      assert changeset.valid?

      # Invalid - custom link without title
      invalid_custom = [
        %{"type" => "custom", "url" => "https://example.com"}
      ]
      changeset = EnrichedPodcast.changeset(%EnrichedPodcast{}, Map.put(base_attrs, :links, invalid_custom))
      refute changeset.valid?

      # Invalid - unknown type
      invalid_type = [
        %{"type" => "unknown", "url" => "https://example.com"}
      ]
      changeset = EnrichedPodcast.changeset(%EnrichedPodcast{}, Map.put(base_attrs, :links, invalid_type))
      refute changeset.valid?
    end

    test "links cannot exceed 10" do
      base_attrs = %{
        feed_url: "https://example.com/feed.xml",
        slug: "my-podcast",
        created_by_user_id: Ecto.UUID.generate()
      }

      # 10 links - valid
      links_10 = Enum.map(1..10, fn i ->
        %{"type" => "twitter", "url" => "https://twitter.com/podcast#{i}"}
      end)
      changeset = EnrichedPodcast.changeset(%EnrichedPodcast{}, Map.put(base_attrs, :links, links_10))
      assert changeset.valid?

      # 11 links - invalid
      links_11 = Enum.map(1..11, fn i ->
        %{"type" => "twitter", "url" => "https://twitter.com/podcast#{i}"}
      end)
      changeset = EnrichedPodcast.changeset(%EnrichedPodcast{}, Map.put(base_attrs, :links, links_11))
      refute changeset.valid?
    end
  end

  describe "social_types/0" do
    test "returns list of supported social network types" do
      types = EnrichedPodcast.social_types()
      assert "twitter" in types
      assert "mastodon" in types
      assert "instagram" in types
      assert "youtube" in types
      assert "spotify" in types
      assert "apple_podcasts" in types
    end
  end
end
