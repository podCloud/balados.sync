defmodule BaladosSyncProjections.Schemas.UserPodcastSettings do
  @moduledoc """
  Schema for user-specific podcast settings.

  Stores per-user preferences for claimed podcasts, including:
  - visibility: Whether the podcast appears on the user's public profile

  This is a system table (not event-sourced), managed directly via Ecto.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @schema_prefix "system"

  @valid_visibilities ~w(public private)

  schema "user_podcast_settings" do
    field :user_id, :string
    field :visibility, :string, default: "private"

    belongs_to :enriched_podcast, BaladosSyncProjections.Schemas.EnrichedPodcast, type: :binary_id

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(settings, attrs) do
    settings
    |> cast(attrs, [:user_id, :enriched_podcast_id, :visibility])
    |> validate_required([:user_id, :enriched_podcast_id, :visibility])
    |> validate_inclusion(:visibility, @valid_visibilities)
    |> unique_constraint([:user_id, :enriched_podcast_id])
  end

  @doc """
  Returns the list of valid visibility options.
  """
  def valid_visibilities, do: @valid_visibilities
end
