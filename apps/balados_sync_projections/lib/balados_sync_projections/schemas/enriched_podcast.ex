defmodule BaladosSyncProjections.Schemas.EnrichedPodcast do
  @moduledoc """
  Schema for enriched podcast entries.

  Enriched podcasts allow admins to create custom URL slugs, branding options,
  and social links for featured podcasts.

  This is a system table (not event-sourced), managed directly via Ecto.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @schema_prefix "system"

  @social_types ["twitter", "mastodon", "instagram", "youtube", "spotify", "apple_podcasts"]

  schema "enriched_podcasts" do
    field :feed_url, :string
    field :slug, :string
    field :background_color, :string
    field :links, {:array, :map}, default: []
    field :created_by_user_id, :binary_id

    timestamps(type: :utc_datetime)
  end

  @doc """
  Changeset for creating or updating an enriched podcast.

  Links format:
  [
    %{"type" => "twitter", "url" => "https://twitter.com/..."},
    %{"type" => "custom", "title" => "Website", "url" => "https://..."}
  ]

  Supported social types: #{Enum.join(@social_types, ", ")}
  """
  def changeset(enriched_podcast, attrs) do
    enriched_podcast
    |> cast(attrs, [:feed_url, :slug, :background_color, :links, :created_by_user_id])
    |> validate_required([:feed_url, :slug, :created_by_user_id])
    |> validate_slug()
    |> validate_background_color()
    |> validate_links()
    |> unique_constraint(:slug)
    |> unique_constraint(:feed_url)
  end

  @doc """
  Returns the list of supported social network types.
  """
  def social_types, do: @social_types

  defp validate_slug(changeset) do
    changeset
    |> validate_format(:slug, ~r/^[a-z0-9\-]{3,50}$/,
      message: "must be 3-50 lowercase letters, numbers, or hyphens"
    )
    |> validate_not_base64_like(:slug)
  end

  defp validate_not_base64_like(changeset, field) do
    validate_change(changeset, field, fn _, value ->
      # Reject if it looks like base64 (contains uppercase, +, /, or =)
      if String.match?(value, ~r/[A-Z+\/=]/) do
        [{field, "cannot look like base64 encoding"}]
      else
        []
      end
    end)
  end

  defp validate_background_color(changeset) do
    case get_change(changeset, :background_color) do
      nil ->
        changeset

      "" ->
        changeset

      _color ->
        validate_format(changeset, :background_color, ~r/^#[0-9A-Fa-f]{6}$/,
          message: "must be a valid hex color (#RRGGBB)"
        )
    end
  end

  defp validate_links(changeset) do
    validate_change(changeset, :links, fn _, links ->
      cond do
        length(links) > 10 ->
          [links: "cannot have more than 10 links"]

        not Enum.all?(links, &valid_link?/1) ->
          [links: "contains invalid link format"]

        true ->
          []
      end
    end)
  end

  defp valid_link?(%{"type" => "custom", "title" => title, "url" => url})
       when is_binary(title) and is_binary(url) do
    String.length(title) > 0 and valid_url?(url)
  end

  defp valid_link?(%{"type" => type, "url" => url}) when is_binary(url) do
    type in @social_types and valid_url?(url)
  end

  defp valid_link?(_), do: false

  defp valid_url?(url) do
    uri = URI.parse(url)

    uri.scheme in ["http", "https"] and
      is_binary(uri.host) and
      String.length(uri.host) > 0 and
      not localhost_or_private?(uri.host)
  end

  # Block localhost, loopback, and common private IP ranges
  defp localhost_or_private?(host) do
    String.match?(host, ~r/^(localhost|127\.|10\.|192\.168\.|172\.(1[6-9]|2[0-9]|3[0-1])\.|0\.0\.0\.0|::1|\[::1\])/i)
  end
end
