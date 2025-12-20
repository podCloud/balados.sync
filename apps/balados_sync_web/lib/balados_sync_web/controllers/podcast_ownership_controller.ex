defmodule BaladosSyncWeb.PodcastOwnershipController do
  @moduledoc """
  Web controller for podcast ownership claims and verification.

  Provides HTML interface for:
  - Initiating ownership claims
  - Viewing verification instructions
  - Triggering verification
  - Managing claimed podcasts
  - Updating visibility settings
  """

  use BaladosSyncWeb, :controller

  alias BaladosSyncWeb.PodcastOwnership

  plug :require_authenticated_user

  defp require_authenticated_user(conn, _opts) do
    if conn.assigns[:current_user] do
      conn
    else
      conn
      |> put_flash(:error, "You must log in to access this page.")
      |> redirect(to: ~p"/users/log_in")
      |> halt()
    end
  end

  @doc """
  Lists all claimed podcasts and pending claims for the current user.
  """
  def index(conn, _params) do
    user_id = conn.assigns.current_user.id

    claimed_podcasts = PodcastOwnership.list_user_administered_podcasts(user_id)
    pending_claims = PodcastOwnership.list_pending_claims(user_id)

    render(conn, :index,
      claimed_podcasts: claimed_podcasts,
      pending_claims: pending_claims
    )
  end

  @doc """
  Shows form to initiate a new ownership claim.
  """
  def new(conn, _params) do
    render(conn, :new)
  end

  @doc """
  Creates a new ownership claim and shows verification instructions.
  """
  def create(conn, %{"claim" => claim_params}) do
    user_id = conn.assigns.current_user.id
    feed_url = claim_params["feed_url"]

    case PodcastOwnership.request_ownership(user_id, feed_url) do
      {:ok, claim} ->
        conn
        |> put_flash(:info, "Claim initiated! Add the verification code to your RSS feed.")
        |> redirect(to: ~p"/podcast-ownership/claims/#{claim.id}")

      {:error, :pending_claim_exists, existing_claim} ->
        conn
        |> put_flash(:info, "You already have a pending claim for this podcast.")
        |> redirect(to: ~p"/podcast-ownership/claims/#{existing_claim.id}")

      {:error, changeset} ->
        conn
        |> put_flash(:error, "Error creating claim: #{format_errors(changeset)}")
        |> render(:new)
    end
  end

  @doc """
  Shows claim details with verification instructions.
  """
  def show_claim(conn, %{"id" => claim_id}) do
    user_id = conn.assigns.current_user.id
    claim = PodcastOwnership.get_claim(claim_id)

    cond do
      is_nil(claim) ->
        conn
        |> put_flash(:error, "Claim not found.")
        |> redirect(to: ~p"/podcast-ownership")

      claim.user_id != user_id ->
        conn
        |> put_flash(:error, "You don't have access to this claim.")
        |> redirect(to: ~p"/podcast-ownership")

      true ->
        render(conn, :show_claim, claim: claim)
    end
  end

  @doc """
  Triggers verification for a pending claim.
  """
  def verify(conn, %{"id" => claim_id}) do
    user_id = conn.assigns.current_user.id

    case PodcastOwnership.verify_ownership(claim_id, user_id) do
      {:ok, enriched_podcast} ->
        conn
        |> put_flash(:info, "Verification successful! You are now an admin of this podcast.")
        |> redirect(to: ~p"/podcast-ownership/podcasts/#{enriched_podcast.id}")

      {:error, :code_not_found} ->
        conn
        |> put_flash(:error, "Verification code not found in the RSS feed. Make sure you added it and the feed is updated.")
        |> redirect(to: ~p"/podcast-ownership/claims/#{claim_id}")

      {:error, :claim_expired} ->
        conn
        |> put_flash(:error, "This claim has expired. Please create a new one.")
        |> redirect(to: ~p"/podcast-ownership")

      {:error, :rate_limit_exceeded} ->
        conn
        |> put_flash(:error, "Too many verification attempts. Please wait before trying again.")
        |> redirect(to: ~p"/podcast-ownership/claims/#{claim_id}")

      {:error, :claim_not_pending} ->
        conn
        |> put_flash(:error, "This claim is no longer pending.")
        |> redirect(to: ~p"/podcast-ownership")

      {:error, reason} ->
        conn
        |> put_flash(:error, "Verification failed: #{inspect(reason)}")
        |> redirect(to: ~p"/podcast-ownership/claims/#{claim_id}")
    end
  end

  @doc """
  Cancels a pending claim.
  """
  def cancel_claim(conn, %{"id" => claim_id}) do
    user_id = conn.assigns.current_user.id

    case PodcastOwnership.cancel_claim(claim_id, user_id) do
      {:ok, _claim} ->
        conn
        |> put_flash(:info, "Claim cancelled.")
        |> redirect(to: ~p"/podcast-ownership")

      {:error, :claim_not_found} ->
        conn
        |> put_flash(:error, "Claim not found.")
        |> redirect(to: ~p"/podcast-ownership")

      {:error, :claim_not_pending} ->
        conn
        |> put_flash(:error, "Only pending claims can be cancelled.")
        |> redirect(to: ~p"/podcast-ownership")

      {:error, reason} ->
        conn
        |> put_flash(:error, "Error cancelling claim: #{inspect(reason)}")
        |> redirect(to: ~p"/podcast-ownership")
    end
  end

  @doc """
  Shows a claimed podcast with management options.
  """
  def show_podcast(conn, %{"id" => podcast_id}) do
    user_id = conn.assigns.current_user.id
    podcasts = PodcastOwnership.list_user_administered_podcasts(user_id)
    podcast = Enum.find(podcasts, &(&1.id == podcast_id))

    if podcast do
      # Get user settings for visibility
      settings = BaladosSyncCore.SystemRepo.get_by(
        BaladosSyncProjections.Schemas.UserPodcastSettings,
        user_id: user_id,
        enriched_podcast_id: podcast_id
      )

      render(conn, :show_podcast, podcast: podcast, settings: settings)
    else
      conn
      |> put_flash(:error, "Podcast not found or you don't have access.")
      |> redirect(to: ~p"/podcast-ownership")
    end
  end

  @doc """
  Updates visibility for a claimed podcast.
  """
  def update_visibility(conn, %{"id" => podcast_id, "visibility" => visibility}) do
    user_id = conn.assigns.current_user.id

    case PodcastOwnership.update_visibility(user_id, podcast_id, visibility) do
      {:ok, _settings} ->
        visibility_text = if visibility == "public", do: "public", else: "private"

        conn
        |> put_flash(:info, "Podcast is now #{visibility_text}.")
        |> redirect(to: ~p"/podcast-ownership/podcasts/#{podcast_id}")

      {:error, :settings_not_found} ->
        conn
        |> put_flash(:error, "Settings not found. Are you an admin of this podcast?")
        |> redirect(to: ~p"/podcast-ownership")

      {:error, reason} ->
        conn
        |> put_flash(:error, "Error updating visibility: #{inspect(reason)}")
        |> redirect(to: ~p"/podcast-ownership/podcasts/#{podcast_id}")
    end
  end

  @doc """
  Relinquishes ownership of a podcast.
  """
  def relinquish(conn, %{"id" => podcast_id}) do
    user_id = conn.assigns.current_user.id

    case PodcastOwnership.relinquish_ownership(podcast_id, user_id) do
      {:ok, _podcast} ->
        conn
        |> put_flash(:info, "You have relinquished ownership of this podcast.")
        |> redirect(to: ~p"/podcast-ownership")

      {:error, :podcast_not_found} ->
        conn
        |> put_flash(:error, "Podcast not found.")
        |> redirect(to: ~p"/podcast-ownership")

      {:error, :not_an_admin} ->
        conn
        |> put_flash(:error, "You are not an admin of this podcast.")
        |> redirect(to: ~p"/podcast-ownership")

      {:error, reason} ->
        conn
        |> put_flash(:error, "Error relinquishing ownership: #{inspect(reason)}")
        |> redirect(to: ~p"/podcast-ownership/podcasts/#{podcast_id}")
    end
  end

  # Helpers

  defp format_errors(%Ecto.Changeset{} = changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Enum.reduce(opts, msg, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)
    end)
    |> Enum.map(fn {field, errors} -> "#{field}: #{Enum.join(errors, ", ")}" end)
    |> Enum.join("; ")
  end

  defp format_errors(error), do: inspect(error)
end
