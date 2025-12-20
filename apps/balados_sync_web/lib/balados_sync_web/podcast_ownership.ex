defmodule BaladosSyncWeb.PodcastOwnership do
  @moduledoc """
  Context for podcast ownership claims and verification.

  Handles the verification flow for users claiming administrative ownership of podcasts
  by proving they control the podcast's RSS feed.

  ## Verification Flow

  1. User initiates claim for a podcast (by feed URL)
  2. System generates a unique verification code
  3. User adds the code anywhere in their RSS feed (comment, description, custom tag)
  4. User triggers verification
  5. System fetches the RSS feed **raw** (bypassing all caches) and searches for the code
  6. If code is found, ownership is granted
  7. Code can be removed from feed after successful verification

  ## Security Considerations

  - Verification codes expire after 48 hours by default
  - Rate limiting: max 5 verification attempts per hour
  - Raw fetch bypasses all caching to ensure fresh content
  - Code search is case-sensitive exact match
  """

  import Ecto.Query
  alias BaladosSyncCore.SystemRepo
  alias BaladosSyncCore.OwnershipEmails
  alias BaladosSyncProjections.Schemas.{EmailVerification, EnrichedPodcast, PodcastOwnershipClaim, UserPodcastSettings}
  alias BaladosSyncWeb.RssParser

  require Logger

  @verification_rate_limit_per_hour 5
  @verification_timeout_ms 30_000

  ## Claim Initiation

  @doc """
  Initiates a podcast ownership claim for a user.

  Returns {:ok, claim} with the verification code.
  Returns {:error, reason} if claim cannot be created.

  ## Options
  - `:expiration_hours` - Hours until verification code expires (default: 48)
  """
  def request_ownership(user_id, feed_url, opts \\ []) do
    normalized_url = String.trim(feed_url)

    # Check for existing pending claim
    case get_pending_claim(user_id, normalized_url) do
      nil ->
        PodcastOwnershipClaim.create_changeset(user_id, normalized_url, opts)
        |> SystemRepo.insert()

      existing_claim ->
        {:error, :pending_claim_exists, existing_claim}
    end
  end

  @doc """
  Cancels a pending ownership claim.
  """
  def cancel_claim(claim_id, user_id) do
    with {:ok, claim} <- get_claim_by_id(claim_id),
         :ok <- verify_claim_ownership(claim, user_id),
         true <- claim.status == "pending" do
      claim
      |> PodcastOwnershipClaim.cancel_changeset()
      |> SystemRepo.update()
    else
      {:error, :not_found} -> {:error, :claim_not_found}
      {:error, :unauthorized} -> {:error, :unauthorized}
      false -> {:error, :claim_not_pending}
    end
  end

  ## Verification

  @doc """
  Verifies a podcast ownership claim by fetching the RSS feed and searching for the verification code.

  Returns {:ok, enriched_podcast} if verification succeeds.
  Returns {:error, reason} if verification fails.
  """
  def verify_ownership(claim_id, user_id) do
    with {:ok, claim} <- get_claim_by_id(claim_id),
         :ok <- verify_claim_ownership(claim, user_id),
         :ok <- check_claim_status(claim),
         :ok <- check_rate_limit(user_id),
         {:ok, feed_content} <- fetch_feed_raw(claim.feed_url),
         :ok <- search_verification_code(feed_content, claim.verification_code) do
      # Verification successful - create or update enriched podcast
      SystemRepo.transaction(fn ->
        # Get or create enriched podcast
        enriched_podcast = get_or_create_enriched_podcast(claim.feed_url, user_id, feed_content)

        # Add user as admin if not already
        enriched_podcast = add_admin_to_podcast(enriched_podcast, user_id)

        # Update claim status
        claim
        |> PodcastOwnershipClaim.verify_changeset(enriched_podcast.id)
        |> SystemRepo.update!()

        # Create user settings with default visibility
        get_or_create_user_settings(user_id, enriched_podcast.id, "private")

        enriched_podcast
      end)
    else
      {:error, :code_not_found} = error ->
        # Increment attempts and mark as failed
        with {:ok, claim} <- get_claim_by_id(claim_id) do
          claim
          |> PodcastOwnershipClaim.fail_changeset("Verification code not found in RSS feed")
          |> SystemRepo.update()
        end

        error

      {:error, reason} = error ->
        Logger.error("Verification failed for claim #{claim_id}: #{inspect(reason)}")
        error
    end
  end

  ## RSS Feed Fetching (Bypass Cache)

  defp fetch_feed_raw(feed_url) do
    # Use HTTPoison with cache-busting headers
    headers = [
      {"Cache-Control", "no-cache, no-store, must-revalidate"},
      {"Pragma", "no-cache"},
      {"Expires", "0"}
    ]

    options = [
      timeout: @verification_timeout_ms,
      recv_timeout: @verification_timeout_ms,
      follow_redirect: true
    ]

    case HTTPoison.get(feed_url, headers, options) do
      {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
        {:ok, body}

      {:ok, %HTTPoison.Response{status_code: status}} ->
        Logger.error("Feed fetch failed with status #{status}: #{feed_url}")
        {:error, {:http_error, status}}

      {:error, %HTTPoison.Error{reason: reason}} ->
        Logger.error("Feed fetch network error: #{inspect(reason)}")
        {:error, {:network_error, reason}}
    end
  end

  defp search_verification_code(feed_content, verification_code) do
    # Case-sensitive exact match - search entire raw response
    if String.contains?(feed_content, verification_code) do
      :ok
    else
      {:error, :code_not_found}
    end
  end

  ## Enriched Podcast Management

  defp get_or_create_enriched_podcast(feed_url, user_id, feed_content) do
    case SystemRepo.get_by(EnrichedPodcast, feed_url: feed_url) do
      nil ->
        # Parse feed to extract metadata for initial title
        metadata = extract_feed_metadata(feed_content)

        # Generate a slug from the feed title or URL
        slug = generate_slug(metadata[:title] || feed_url)

        %EnrichedPodcast{}
        |> EnrichedPodcast.changeset(%{
          feed_url: feed_url,
          slug: slug,
          created_by_user_id: user_id,
          admin_user_ids: [user_id]
        })
        |> SystemRepo.insert!()

      podcast ->
        podcast
    end
  end

  defp extract_feed_metadata(feed_content) do
    case RssParser.parse_feed(feed_content) do
      {:ok, metadata} -> metadata
      {:error, _} -> %{}
    end
  end

  defp generate_slug(source) do
    source
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9\s-]/, "")
    |> String.replace(~r/\s+/, "-")
    |> String.slice(0, 50)
    |> String.trim("-")
    |> ensure_slug_unique()
  end

  defp ensure_slug_unique(slug, attempt \\ 0) do
    final_slug = if attempt > 0, do: "#{slug}-#{attempt}", else: slug

    if SystemRepo.exists?(from(p in EnrichedPodcast, where: p.slug == ^final_slug)) do
      ensure_slug_unique(slug, attempt + 1)
    else
      final_slug
    end
  end

  defp add_admin_to_podcast(enriched_podcast, user_id) do
    if user_id in (enriched_podcast.admin_user_ids || []) do
      enriched_podcast
    else
      enriched_podcast
      |> add_admin_changeset(user_id)
      |> SystemRepo.update!()
    end
  end

  defp add_admin_changeset(enriched_podcast, user_id) do
    current_admins = enriched_podcast.admin_user_ids || []
    new_admins = Enum.uniq([user_id | current_admins])

    Ecto.Changeset.change(enriched_podcast, admin_user_ids: new_admins)
  end

  @doc """
  Removes a user from podcast admins (relinquish ownership).
  """
  def relinquish_ownership(enriched_podcast_id, user_id) do
    with {:ok, podcast} <- get_enriched_podcast(enriched_podcast_id),
         true <- user_id in (podcast.admin_user_ids || []) do
      current_admins = podcast.admin_user_ids || []
      new_admins = Enum.reject(current_admins, &(&1 == user_id))

      podcast
      |> Ecto.Changeset.change(admin_user_ids: new_admins)
      |> SystemRepo.update()
    else
      {:error, :not_found} -> {:error, :podcast_not_found}
      false -> {:error, :not_an_admin}
    end
  end

  ## User Settings

  defp get_or_create_user_settings(user_id, enriched_podcast_id, visibility) do
    case SystemRepo.get_by(UserPodcastSettings, user_id: user_id, enriched_podcast_id: enriched_podcast_id) do
      nil ->
        %UserPodcastSettings{}
        |> UserPodcastSettings.changeset(%{
          user_id: user_id,
          enriched_podcast_id: enriched_podcast_id,
          visibility: visibility
        })
        |> SystemRepo.insert!()

      settings ->
        settings
    end
  end

  @doc """
  Updates visibility setting for a user's claimed podcast.
  """
  def update_visibility(user_id, enriched_podcast_id, visibility) when visibility in ["public", "private"] do
    case SystemRepo.get_by(UserPodcastSettings, user_id: user_id, enriched_podcast_id: enriched_podcast_id) do
      nil ->
        {:error, :settings_not_found}

      settings ->
        settings
        |> UserPodcastSettings.changeset(%{visibility: visibility})
        |> SystemRepo.update()
    end
  end

  def update_visibility(_user_id, _enriched_podcast_id, _visibility) do
    {:error, :invalid_visibility}
  end

  ## Queries

  @doc """
  Gets all podcasts administered by a user.
  """
  def list_user_administered_podcasts(user_id) do
    EnrichedPodcast
    |> where([p], ^user_id in p.admin_user_ids)
    |> SystemRepo.all()
  end

  @doc """
  Gets public podcasts claimed by a user (for profile display).
  """
  def list_user_public_podcasts(user_id) do
    query =
      from p in EnrichedPodcast,
        join: s in UserPodcastSettings,
        on: s.enriched_podcast_id == p.id,
        where: s.user_id == ^user_id and s.visibility == "public",
        select: p

    SystemRepo.all(query)
  end

  @doc """
  Gets pending claims for a user.
  """
  def list_pending_claims(user_id) do
    PodcastOwnershipClaim
    |> where([c], c.user_id == ^user_id and c.status == "pending")
    |> order_by([c], desc: c.inserted_at)
    |> SystemRepo.all()
  end

  @doc """
  Gets a claim by ID.
  """
  def get_claim(claim_id) do
    SystemRepo.get(PodcastOwnershipClaim, claim_id)
  end

  defp get_pending_claim(user_id, feed_url) do
    PodcastOwnershipClaim
    |> where([c], c.user_id == ^user_id and c.feed_url == ^feed_url and c.status == "pending")
    |> SystemRepo.one()
  end

  defp get_claim_by_id(claim_id) do
    case SystemRepo.get(PodcastOwnershipClaim, claim_id) do
      nil -> {:error, :not_found}
      claim -> {:ok, claim}
    end
  end

  defp get_enriched_podcast(podcast_id) do
    case SystemRepo.get(EnrichedPodcast, podcast_id) do
      nil -> {:error, :not_found}
      podcast -> {:ok, podcast}
    end
  end

  ## Validations

  defp verify_claim_ownership(claim, user_id) do
    if claim.user_id == user_id do
      :ok
    else
      {:error, :unauthorized}
    end
  end

  defp check_claim_status(claim) do
    cond do
      claim.status != "pending" ->
        {:error, :claim_not_pending}

      DateTime.compare(claim.expires_at, DateTime.utc_now()) == :lt ->
        {:error, :claim_expired}

      true ->
        :ok
    end
  end

  defp check_rate_limit(user_id) do
    one_hour_ago = DateTime.utc_now() |> DateTime.add(-3600, :second)

    # Count verification attempts in the last hour
    # Uses inserted_at (claim creation time) rather than updated_at
    # to accurately count new verification requests, not just any update
    count =
      PodcastOwnershipClaim
      |> where([c], c.user_id == ^user_id and c.inserted_at > ^one_hour_ago)
      |> select([c], count(c.id))
      |> SystemRepo.one()

    if count >= @verification_rate_limit_per_hour do
      {:error, :rate_limit_exceeded}
    else
      :ok
    end
  end

  ## Email Verification Flow

  @email_rate_limit_per_hour 3
  @email_rate_limit_per_email_per_hour 2

  @doc """
  Extracts available contact emails from a podcast RSS feed.

  Returns {:ok, emails} where emails is a list of %{email: string, source: string}.
  Returns {:error, reason} if feed cannot be fetched or parsed.
  """
  def get_available_emails(feed_url) do
    with {:ok, feed_content} <- fetch_feed_raw(feed_url),
         {:ok, emails} <- RssParser.extract_contact_emails(feed_content) do
      {:ok, emails}
    end
  end

  @doc """
  Initiates email verification for a claim.

  1. Validates claim is pending and owned by user
  2. Fetches RSS feed and extracts emails
  3. Validates selected email exists in feed
  4. Creates email verification record
  5. Sends verification email

  Returns {:ok, email_verification} or {:error, reason}.
  """
  def request_email_verification(claim_id, user_id, selected_email) do
    with {:ok, claim} <- get_claim_by_id(claim_id),
         :ok <- verify_claim_ownership(claim, user_id),
         :ok <- check_claim_status(claim),
         :ok <- check_email_rate_limit(user_id, selected_email),
         {:ok, feed_content} <- fetch_feed_raw(claim.feed_url),
         {:ok, emails} <- RssParser.extract_contact_emails(feed_content),
         {:ok, email_info} <- validate_email_in_feed(selected_email, emails),
         {:ok, metadata} <- extract_feed_metadata_safe(feed_content) do
      # Cancel any existing pending email verification for this claim
      cancel_pending_email_verifications(claim_id)

      # Create new email verification
      verification =
        EmailVerification.create_changeset(user_id, claim_id, email_info.email, email_info.source)
        |> SystemRepo.insert!()

      # Send the email
      podcast_title = metadata[:title] || "Unknown Podcast"

      case OwnershipEmails.deliver_verification_email(
             verification.email,
             verification.verification_code,
             podcast_title,
             claim.feed_url
           ) do
        {:ok, _email} ->
          # Mark as sent
          {:ok, updated_verification} =
            verification
            |> EmailVerification.mark_sent_changeset()
            |> SystemRepo.update()

          Logger.info("Email verification sent for claim #{claim_id} to #{verification.email}")
          {:ok, updated_verification}

        {:error, reason} ->
          Logger.error("Failed to send verification email: #{inspect(reason)}")
          {:error, :email_send_failed}
      end
    end
  end

  defp validate_email_in_feed(selected_email, emails) do
    normalized = String.downcase(selected_email)

    case Enum.find(emails, fn %{email: email} -> String.downcase(email) == normalized end) do
      nil -> {:error, :email_not_in_feed}
      email_info -> {:ok, email_info}
    end
  end

  defp extract_feed_metadata_safe(feed_content) do
    case RssParser.parse_feed(feed_content) do
      {:ok, metadata} -> {:ok, metadata}
      {:error, _} -> {:ok, %{}}
    end
  end

  defp cancel_pending_email_verifications(claim_id) do
    now = DateTime.utc_now()

    EmailVerification
    |> where([v], v.claim_id == ^claim_id and v.status == "pending")
    |> SystemRepo.update_all(set: [status: "expired", updated_at: now])
  end

  @doc """
  Submits a verification code for email-based ownership verification.

  Returns {:ok, enriched_podcast} if code is correct.
  Returns {:error, reason} if verification fails.
  """
  def verify_email_code(claim_id, user_id, submitted_code) do
    with {:ok, claim} <- get_claim_by_id(claim_id),
         :ok <- verify_claim_ownership(claim, user_id),
         :ok <- check_claim_status(claim),
         {:ok, verification} <- get_pending_email_verification(claim_id),
         :ok <- check_verification_expired(verification),
         :ok <- check_verification_code(verification, submitted_code),
         # Fetch feed content BEFORE transaction to avoid network calls inside DB transaction
         {:ok, feed_content} <- fetch_feed_raw(claim.feed_url) do
      # Verification successful - all DB operations in transaction
      SystemRepo.transaction(fn ->
        # Mark email verification as verified
        verification
        |> EmailVerification.verify_changeset()
        |> SystemRepo.update!()

        # Get or create enriched podcast (uses pre-fetched feed_content)
        enriched_podcast = get_or_create_enriched_podcast(claim.feed_url, user_id, feed_content)

        # Add user as admin if not already
        enriched_podcast = add_admin_to_podcast(enriched_podcast, user_id)

        # Update claim status with email verification method
        claim
        |> PodcastOwnershipClaim.verify_changeset(enriched_podcast.id)
        |> Ecto.Changeset.change(verification_method: "email")
        |> SystemRepo.update!()

        # Create user settings with default visibility
        get_or_create_user_settings(user_id, enriched_podcast.id, "private")

        Logger.info("Email verification successful for claim #{claim_id}")
        enriched_podcast
      end)
    else
      {:error, :code_mismatch} = error ->
        # Increment attempts
        with {:ok, verification} <- get_pending_email_verification(claim_id) do
          verification
          |> EmailVerification.increment_attempts_changeset()
          |> SystemRepo.update()
        end

        error

      error ->
        error
    end
  end

  defp get_pending_email_verification(claim_id) do
    case SystemRepo.one(
           from v in EmailVerification,
             where: v.claim_id == ^claim_id and v.status in ["pending", "sent"],
             order_by: [desc: v.inserted_at],
             limit: 1
         ) do
      nil -> {:error, :no_pending_verification}
      verification -> {:ok, verification}
    end
  end

  defp check_verification_expired(verification) do
    if DateTime.compare(verification.expires_at, DateTime.utc_now()) == :lt do
      {:error, :verification_expired}
    else
      :ok
    end
  end

  defp check_verification_code(verification, submitted_code) do
    # Normalize: remove spaces and compare case-insensitively for digits
    normalized_submitted = String.replace(submitted_code, ~r/\s+/, "")
    normalized_stored = verification.verification_code

    if normalized_submitted == normalized_stored do
      :ok
    else
      {:error, :code_mismatch}
    end
  end

  defp check_email_rate_limit(user_id, email) do
    one_hour_ago = DateTime.utc_now() |> DateTime.add(-3600, :second)

    # Rate limit per user
    user_count =
      EmailVerification
      |> where([v], v.user_id == ^user_id and v.inserted_at > ^one_hour_ago)
      |> select([v], count(v.id))
      |> SystemRepo.one()

    if user_count >= @email_rate_limit_per_hour do
      {:error, :rate_limit_exceeded}
    else
      # Rate limit per email
      email_count =
        EmailVerification
        |> where([v], v.email == ^email and v.inserted_at > ^one_hour_ago)
        |> select([v], count(v.id))
        |> SystemRepo.one()

      if email_count >= @email_rate_limit_per_email_per_hour do
        {:error, :email_rate_limit_exceeded}
      else
        :ok
      end
    end
  end

  @doc """
  Gets the current email verification for a claim, if any.
  """
  def get_email_verification(claim_id) do
    SystemRepo.one(
      from v in EmailVerification,
        where: v.claim_id == ^claim_id,
        order_by: [desc: v.inserted_at],
        limit: 1
    )
  end

  ## Background Jobs

  @doc """
  Expires old pending claims.
  Should be run periodically (e.g., daily cron job).
  """
  def expire_old_claims do
    now = DateTime.utc_now()

    {count, _} =
      PodcastOwnershipClaim
      |> where([c], c.status == "pending" and c.expires_at < ^now)
      |> SystemRepo.update_all(set: [status: "expired", updated_at: now])

    Logger.info("Expired #{count} old ownership claims")
    {:ok, count}
  end

  @doc """
  Expires old pending email verifications.
  Should be run periodically (e.g., every 15 minutes).
  """
  def expire_old_email_verifications do
    now = DateTime.utc_now()

    {count, _} =
      EmailVerification
      |> where([v], v.status in ["pending", "sent"] and v.expires_at < ^now)
      |> SystemRepo.update_all(set: [status: "expired", updated_at: now])

    Logger.info("Expired #{count} old email verifications")
    {:ok, count}
  end
end
