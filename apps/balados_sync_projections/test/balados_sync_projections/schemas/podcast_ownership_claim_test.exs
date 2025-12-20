defmodule BaladosSyncProjections.Schemas.PodcastOwnershipClaimTest do
  @moduledoc """
  Tests for PodcastOwnershipClaim schema and verification code generation.
  """

  use ExUnit.Case

  alias BaladosSyncProjections.Schemas.PodcastOwnershipClaim

  describe "generate_verification_code/0" do
    test "generates code in expected format" do
      code = PodcastOwnershipClaim.generate_verification_code()

      assert String.starts_with?(code, "balados-verify-")
      # Total length: "balados-verify-" (15) + 32 hex chars = 47
      assert String.length(code) == 47
    end

    test "generates unique codes" do
      codes = for _ <- 1..100, do: PodcastOwnershipClaim.generate_verification_code()
      unique_codes = Enum.uniq(codes)

      # All codes should be unique (cryptographically random)
      assert length(codes) == length(unique_codes)
    end

    test "generates lowercase hex suffix" do
      code = PodcastOwnershipClaim.generate_verification_code()
      suffix = String.replace_prefix(code, "balados-verify-", "")

      # Suffix should be lowercase hex
      assert String.match?(suffix, ~r/^[a-f0-9]{32}$/)
    end
  end

  describe "create_changeset/3" do
    test "creates valid changeset with required fields" do
      changeset = PodcastOwnershipClaim.create_changeset("user-123", "https://example.com/feed.xml")

      assert changeset.valid?
      assert Ecto.Changeset.get_field(changeset, :user_id) == "user-123"
      assert Ecto.Changeset.get_field(changeset, :feed_url) == "https://example.com/feed.xml"
      assert Ecto.Changeset.get_field(changeset, :status) == "pending"
      assert Ecto.Changeset.get_field(changeset, :verification_attempts) == 0
    end

    test "generates verification code automatically" do
      changeset = PodcastOwnershipClaim.create_changeset("user-123", "https://example.com/feed.xml")
      code = Ecto.Changeset.get_field(changeset, :verification_code)

      assert String.starts_with?(code, "balados-verify-")
    end

    test "sets expiration to 48 hours by default" do
      changeset = PodcastOwnershipClaim.create_changeset("user-123", "https://example.com/feed.xml")
      expires_at = Ecto.Changeset.get_field(changeset, :expires_at)

      expected_expires = DateTime.utc_now() |> DateTime.add(48 * 3600, :second)
      # Allow 5 second tolerance
      diff = DateTime.diff(expires_at, expected_expires)
      assert diff >= -5 and diff <= 5
    end

    test "respects custom expiration_hours option" do
      changeset =
        PodcastOwnershipClaim.create_changeset("user-123", "https://example.com/feed.xml",
          expiration_hours: 24
        )

      expires_at = Ecto.Changeset.get_field(changeset, :expires_at)
      expected_expires = DateTime.utc_now() |> DateTime.add(24 * 3600, :second)
      diff = DateTime.diff(expires_at, expected_expires)
      assert diff >= -5 and diff <= 5
    end
  end

  describe "verify_changeset/2" do
    test "sets status to verified and records time" do
      claim = %PodcastOwnershipClaim{
        id: Ecto.UUID.generate(),
        status: "pending",
        verification_attempts: 1
      }

      changeset = PodcastOwnershipClaim.verify_changeset(claim, Ecto.UUID.generate())

      assert Ecto.Changeset.get_field(changeset, :status) == "verified"
      assert Ecto.Changeset.get_field(changeset, :verified_at) != nil
    end

    test "associates with enriched_podcast_id" do
      claim = %PodcastOwnershipClaim{id: Ecto.UUID.generate(), status: "pending"}
      podcast_id = Ecto.UUID.generate()

      changeset = PodcastOwnershipClaim.verify_changeset(claim, podcast_id)

      assert Ecto.Changeset.get_field(changeset, :enriched_podcast_id) == podcast_id
    end
  end

  describe "fail_changeset/2" do
    test "sets status to failed with reason" do
      claim = %PodcastOwnershipClaim{
        id: Ecto.UUID.generate(),
        status: "pending",
        verification_attempts: 2
      }

      changeset = PodcastOwnershipClaim.fail_changeset(claim, "code_not_found")

      assert Ecto.Changeset.get_field(changeset, :status) == "failed"
      assert Ecto.Changeset.get_field(changeset, :failure_reason) == "code_not_found"
    end

    test "increments verification_attempts" do
      claim = %PodcastOwnershipClaim{
        id: Ecto.UUID.generate(),
        status: "pending",
        verification_attempts: 2
      }

      changeset = PodcastOwnershipClaim.fail_changeset(claim, "reason")

      assert Ecto.Changeset.get_field(changeset, :verification_attempts) == 3
    end

    test "handles nil verification_attempts" do
      claim = %PodcastOwnershipClaim{
        id: Ecto.UUID.generate(),
        status: "pending",
        verification_attempts: nil
      }

      changeset = PodcastOwnershipClaim.fail_changeset(claim, "reason")

      assert Ecto.Changeset.get_field(changeset, :verification_attempts) == 1
    end
  end

  describe "increment_attempts_changeset/1" do
    test "increments verification_attempts without changing status" do
      claim = %PodcastOwnershipClaim{
        id: Ecto.UUID.generate(),
        status: "pending",
        verification_attempts: 0
      }

      changeset = PodcastOwnershipClaim.increment_attempts_changeset(claim)

      assert Ecto.Changeset.get_field(changeset, :verification_attempts) == 1
      # Status unchanged - should still be the original value from claim
      refute Ecto.Changeset.get_change(changeset, :status)
    end
  end

  describe "expire_changeset/1" do
    test "sets status to expired" do
      claim = %PodcastOwnershipClaim{id: Ecto.UUID.generate(), status: "pending"}

      changeset = PodcastOwnershipClaim.expire_changeset(claim)

      assert Ecto.Changeset.get_field(changeset, :status) == "expired"
    end
  end

  describe "cancel_changeset/1" do
    test "sets status to cancelled" do
      claim = %PodcastOwnershipClaim{id: Ecto.UUID.generate(), status: "pending"}

      changeset = PodcastOwnershipClaim.cancel_changeset(claim)

      assert Ecto.Changeset.get_field(changeset, :status) == "cancelled"
    end
  end

  describe "valid_statuses/0" do
    test "returns expected status list" do
      statuses = PodcastOwnershipClaim.valid_statuses()

      assert "pending" in statuses
      assert "verified" in statuses
      assert "failed" in statuses
      assert "expired" in statuses
      assert "cancelled" in statuses
      assert length(statuses) == 5
    end
  end

  describe "changeset/2 validations" do
    test "requires user_id" do
      changeset =
        PodcastOwnershipClaim.changeset(%PodcastOwnershipClaim{}, %{
          feed_url: "https://example.com",
          verification_code: "balados-verify-test",
          expires_at: DateTime.utc_now()
        })

      refute changeset.valid?
      assert {:user_id, _} = List.keyfind(changeset.errors, :user_id, 0)
    end

    test "requires feed_url" do
      changeset =
        PodcastOwnershipClaim.changeset(%PodcastOwnershipClaim{}, %{
          user_id: "user-123",
          verification_code: "balados-verify-test",
          expires_at: DateTime.utc_now()
        })

      refute changeset.valid?
      assert {:feed_url, _} = List.keyfind(changeset.errors, :feed_url, 0)
    end

    test "requires verification_code" do
      changeset =
        PodcastOwnershipClaim.changeset(%PodcastOwnershipClaim{}, %{
          user_id: "user-123",
          feed_url: "https://example.com",
          expires_at: DateTime.utc_now()
        })

      refute changeset.valid?
      assert {:verification_code, _} = List.keyfind(changeset.errors, :verification_code, 0)
    end

    test "requires expires_at" do
      changeset =
        PodcastOwnershipClaim.changeset(%PodcastOwnershipClaim{}, %{
          user_id: "user-123",
          feed_url: "https://example.com",
          verification_code: "balados-verify-test"
        })

      refute changeset.valid?
      assert {:expires_at, _} = List.keyfind(changeset.errors, :expires_at, 0)
    end

    test "validates status inclusion" do
      changeset =
        PodcastOwnershipClaim.changeset(%PodcastOwnershipClaim{}, %{
          user_id: "user-123",
          feed_url: "https://example.com",
          verification_code: "balados-verify-test",
          expires_at: DateTime.utc_now(),
          status: "invalid_status"
        })

      refute changeset.valid?
      assert {:status, _} = List.keyfind(changeset.errors, :status, 0)
    end

    test "accepts valid status" do
      for status <- ~w(pending verified failed expired cancelled) do
        changeset =
          PodcastOwnershipClaim.changeset(%PodcastOwnershipClaim{}, %{
            user_id: "user-123",
            feed_url: "https://example.com",
            verification_code: "balados-verify-test",
            expires_at: DateTime.utc_now(),
            status: status
          })

        assert changeset.valid?, "Expected status '#{status}' to be valid"
      end
    end
  end
end
