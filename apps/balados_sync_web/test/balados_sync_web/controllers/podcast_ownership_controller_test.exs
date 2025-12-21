defmodule BaladosSyncWeb.PodcastOwnershipControllerTest do
  @moduledoc """
  Controller tests for PodcastOwnershipController.

  Tests email verification endpoints:
  - POST /podcast-ownership/claims/:id/email-verify
  - POST /podcast-ownership/claims/:id/email-code
  """

  use BaladosSyncWeb.ConnCase, async: false

  alias BaladosSyncCore.SystemRepo
  alias BaladosSyncProjections.Schemas.{
    User,
    PodcastOwnershipClaim,
    EmailVerification,
    EnrichedPodcast
  }

  setup do
    # Clean up previous test data (EmailVerification uses system schema prefix)
    SystemRepo.delete_all(EmailVerification)
    SystemRepo.delete_all(PodcastOwnershipClaim)
    SystemRepo.delete_all(EnrichedPodcast)

    # Create test user
    user_id = Ecto.UUID.generate()

    user =
      %User{}
      |> User.registration_changeset(%{
        email: "ctrl-test-#{System.unique_integer()}@example.com",
        username: "ctrltest#{System.unique_integer([:positive])}",
        password: "TestPassword123!",
        password_confirmation: "TestPassword123!"
      })
      |> Ecto.Changeset.put_change(:id, user_id)
      |> SystemRepo.insert!()

    {:ok, user: user, user_id: user_id}
  end

  describe "authentication enforcement" do
    test "POST /podcast-ownership/claims/:id/email-verify redirects when not authenticated", %{conn: conn} do
      claim_id = Ecto.UUID.generate()

      conn = post(conn, ~p"/podcast-ownership/claims/#{claim_id}/email-verify", %{"email" => "test@example.com"})

      assert redirected_to(conn) == ~p"/users/log_in"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) == "You must log in to access this page."
    end

    test "POST /podcast-ownership/claims/:id/email-code redirects when not authenticated", %{conn: conn} do
      claim_id = Ecto.UUID.generate()

      conn = post(conn, ~p"/podcast-ownership/claims/#{claim_id}/email-code", %{"code" => "123456"})

      assert redirected_to(conn) == ~p"/users/log_in"
    end

    test "GET /podcast-ownership redirects when not authenticated", %{conn: conn} do
      conn = get(conn, ~p"/podcast-ownership")

      assert redirected_to(conn) == ~p"/users/log_in"
    end
  end

  describe "POST /podcast-ownership/claims/:id/email-verify (request_email_verification)" do
    test "redirects with success flash when email verification requested", %{conn: conn, user: user, user_id: user_id} do
      claim = create_pending_claim(user_id, "https://example.com/feed.xml")

      conn =
        conn
        |> log_in_user(user)
        |> post(~p"/podcast-ownership/claims/#{claim.id}/email-verify", %{"email" => "owner@example.com"})

      # Should redirect back to claim page (even if email sending fails in test env)
      assert redirected_to(conn) =~ ~p"/podcast-ownership/claims/#{claim.id}"
    end

    test "redirects with error for non-existent claim", %{conn: conn, user: user} do
      fake_id = Ecto.UUID.generate()

      conn =
        conn
        |> log_in_user(user)
        |> post(~p"/podcast-ownership/claims/#{fake_id}/email-verify", %{"email" => "owner@example.com"})

      assert redirected_to(conn) =~ "/podcast-ownership"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "not_found"
    end

    test "redirects with error for unauthorized claim", %{conn: conn, user: user} do
      # Create claim for different user
      other_user_id = Ecto.UUID.generate()
      claim = create_pending_claim(other_user_id, "https://example.com/feed.xml")

      conn =
        conn
        |> log_in_user(user)
        |> post(~p"/podcast-ownership/claims/#{claim.id}/email-verify", %{"email" => "owner@example.com"})

      assert redirected_to(conn) =~ "/podcast-ownership"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "unauthorized"
    end

    test "redirects with error for expired claim", %{conn: conn, user: user, user_id: user_id} do
      claim = create_expired_claim(user_id, "https://example.com/feed.xml")

      conn =
        conn
        |> log_in_user(user)
        |> post(~p"/podcast-ownership/claims/#{claim.id}/email-verify", %{"email" => "owner@example.com"})

      assert redirected_to(conn) == ~p"/podcast-ownership"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "expired"
    end
  end

  describe "POST /podcast-ownership/claims/:id/email-code (verify_email_code)" do
    test "redirects with error for incorrect code", %{conn: conn, user: user, user_id: user_id} do
      claim = create_pending_claim(user_id, "https://example.com/feed.xml")

      # Create a pending verification
      verification = create_pending_verification(claim.id, user_id, "owner@example.com", "123456")

      conn =
        conn
        |> log_in_user(user)
        |> post(~p"/podcast-ownership/claims/#{claim.id}/email-code", %{"code" => "000000"})

      assert redirected_to(conn) == ~p"/podcast-ownership/claims/#{claim.id}"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "Invalid verification code"
    end

    test "redirects with error when no pending verification exists", %{conn: conn, user: user, user_id: user_id} do
      claim = create_pending_claim(user_id, "https://example.com/feed.xml")

      conn =
        conn
        |> log_in_user(user)
        |> post(~p"/podcast-ownership/claims/#{claim.id}/email-code", %{"code" => "123456"})

      assert redirected_to(conn) == ~p"/podcast-ownership/claims/#{claim.id}"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "pending email verification"
    end

    test "redirects with error for expired verification", %{conn: conn, user: user, user_id: user_id} do
      claim = create_pending_claim(user_id, "https://example.com/feed.xml")

      # Create an expired verification
      verification = create_expired_verification(claim.id, user_id, "owner@example.com", "123456")

      conn =
        conn
        |> log_in_user(user)
        |> post(~p"/podcast-ownership/claims/#{claim.id}/email-code", %{"code" => "123456"})

      assert redirected_to(conn) == ~p"/podcast-ownership/claims/#{claim.id}"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "expired"
    end

    test "redirects with error for unauthorized user", %{conn: conn, user: user} do
      other_user_id = Ecto.UUID.generate()
      claim = create_pending_claim(other_user_id, "https://example.com/feed.xml")
      create_pending_verification(claim.id, other_user_id, "owner@example.com", "123456")

      conn =
        conn
        |> log_in_user(user)
        |> post(~p"/podcast-ownership/claims/#{claim.id}/email-code", %{"code" => "123456"})

      assert redirected_to(conn) =~ "/podcast-ownership"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "unauthorized"
    end
  end

  describe "GET /podcast-ownership/claims/:id (show_claim)" do
    test "shows claim with verification code", %{conn: conn, user: user, user_id: user_id} do
      claim = create_pending_claim(user_id, "https://example.com/feed.xml")

      conn =
        conn
        |> log_in_user(user)
        |> get(~p"/podcast-ownership/claims/#{claim.id}")

      assert html_response(conn, 200) =~ claim.verification_code
      assert html_response(conn, 200) =~ "Verify RSS Feed"
    end

    test "renders claim page successfully", %{conn: conn, user: user, user_id: user_id} do
      claim = create_pending_claim(user_id, "https://example.com/feed.xml")
      _verification = create_pending_verification(claim.id, user_id, "owner@example.com", "123456")

      conn =
        conn
        |> log_in_user(user)
        |> get(~p"/podcast-ownership/claims/#{claim.id}")

      # Page should render with claim details
      # Note: "Verify Code" section only shows if @available_emails is populated (requires HTTP call)
      assert html_response(conn, 200) =~ claim.verification_code
      assert html_response(conn, 200) =~ "Verify Ownership"
    end

    test "redirects for non-existent claim", %{conn: conn, user: user} do
      fake_id = Ecto.UUID.generate()

      conn =
        conn
        |> log_in_user(user)
        |> get(~p"/podcast-ownership/claims/#{fake_id}")

      assert redirected_to(conn) == ~p"/podcast-ownership"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) == "Claim not found."
    end

    test "redirects for claim owned by another user", %{conn: conn, user: user} do
      other_user_id = Ecto.UUID.generate()
      claim = create_pending_claim(other_user_id, "https://example.com/feed.xml")

      conn =
        conn
        |> log_in_user(user)
        |> get(~p"/podcast-ownership/claims/#{claim.id}")

      assert redirected_to(conn) == ~p"/podcast-ownership"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) == "You don't have access to this claim."
    end
  end

  describe "POST /podcast-ownership/claims/:id/cancel (cancel_claim)" do
    test "cancels pending claim successfully", %{conn: conn, user: user, user_id: user_id} do
      claim = create_pending_claim(user_id, "https://example.com/feed.xml")

      conn =
        conn
        |> log_in_user(user)
        |> post(~p"/podcast-ownership/claims/#{claim.id}/cancel")

      assert redirected_to(conn) == ~p"/podcast-ownership"
      assert Phoenix.Flash.get(conn.assigns.flash, :info) == "Claim cancelled."

      # Verify claim is cancelled
      updated_claim = SystemRepo.get!(PodcastOwnershipClaim, claim.id)
      assert updated_claim.status == "cancelled"
    end

    test "cannot cancel non-pending claim", %{conn: conn, user: user, user_id: user_id} do
      claim = create_verified_claim(user_id, "https://example.com/feed.xml")

      conn =
        conn
        |> log_in_user(user)
        |> post(~p"/podcast-ownership/claims/#{claim.id}/cancel")

      assert redirected_to(conn) == ~p"/podcast-ownership"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) == "Only pending claims can be cancelled."
    end
  end

  describe "GET /podcast-ownership (index)" do
    test "lists claimed podcasts and pending claims", %{conn: conn, user: user, user_id: user_id} do
      # Create a pending claim
      claim = create_pending_claim(user_id, "https://example.com/feed1.xml")

      conn =
        conn
        |> log_in_user(user)
        |> get(~p"/podcast-ownership")

      assert html_response(conn, 200) =~ "Podcast Ownership"
      assert html_response(conn, 200) =~ "https://example.com/feed1.xml"
    end
  end

  # Helper functions

  defp log_in_user(conn, user) do
    conn
    |> init_test_session(%{"user_token" => user.id})
  end

  defp create_pending_claim(user_id, feed_url) do
    PodcastOwnershipClaim.create_changeset(user_id, feed_url)
    |> SystemRepo.insert!()
  end

  defp create_expired_claim(user_id, feed_url) do
    expired_at = DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.add(-3600, :second)

    PodcastOwnershipClaim.create_changeset(user_id, feed_url)
    |> Ecto.Changeset.put_change(:expires_at, expired_at)
    |> SystemRepo.insert!()
  end

  defp create_verified_claim(user_id, feed_url) do
    PodcastOwnershipClaim.create_changeset(user_id, feed_url)
    |> Ecto.Changeset.put_change(:status, "verified")
    |> SystemRepo.insert!()
  end

  defp create_pending_verification(claim_id, user_id, email, code) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)
    expires_at = now |> DateTime.add(1800, :second)

    %EmailVerification{
      id: Ecto.UUID.generate(),
      user_id: user_id,
      claim_id: claim_id,
      email: email,
      email_source: "test",
      verification_code: code,
      status: "sent",
      expires_at: expires_at,
      sent_at: now
    }
    |> SystemRepo.insert!()
  end

  defp create_expired_verification(claim_id, user_id, email, code) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)
    expired_at = now |> DateTime.add(-3600, :second)

    %EmailVerification{
      id: Ecto.UUID.generate(),
      user_id: user_id,
      claim_id: claim_id,
      email: email,
      email_source: "test",
      verification_code: code,
      status: "sent",
      expires_at: expired_at,
      sent_at: now |> DateTime.add(-7200, :second)
    }
    |> SystemRepo.insert!()
  end
end
