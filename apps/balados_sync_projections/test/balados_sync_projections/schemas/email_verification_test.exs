defmodule BaladosSyncProjections.Schemas.EmailVerificationTest do
  @moduledoc """
  Tests for EmailVerification schema and verification code generation.
  """

  use ExUnit.Case

  alias BaladosSyncProjections.Schemas.EmailVerification

  describe "generate_verification_code/0" do
    test "generates 6-digit numeric code" do
      code = EmailVerification.generate_verification_code()

      assert String.length(code) == 6
      assert String.match?(code, ~r/^\d{6}$/)
    end

    test "generates unique codes" do
      codes = for _ <- 1..100, do: EmailVerification.generate_verification_code()
      unique_codes = Enum.uniq(codes)

      # Most codes should be unique (some collisions possible in 1M range)
      assert length(unique_codes) >= 95
    end

    test "pads with leading zeros when needed" do
      # Generate many codes and verify all are 6 digits
      codes = for _ <- 1..50, do: EmailVerification.generate_verification_code()

      for code <- codes do
        assert String.length(code) == 6
      end
    end
  end

  describe "create_changeset/5" do
    test "creates valid changeset with required fields" do
      user_id = "user-123"
      claim_id = Ecto.UUID.generate()
      email = "test@example.com"
      email_source = "itunes:owner"

      changeset = EmailVerification.create_changeset(user_id, claim_id, email, email_source)

      assert changeset.valid?
      assert Ecto.Changeset.get_field(changeset, :user_id) == user_id
      assert Ecto.Changeset.get_field(changeset, :claim_id) == claim_id
      assert Ecto.Changeset.get_field(changeset, :email) == email
      assert Ecto.Changeset.get_field(changeset, :email_source) == email_source
      assert Ecto.Changeset.get_field(changeset, :status) == "pending"
      assert Ecto.Changeset.get_field(changeset, :attempts) == 0
    end

    test "generates verification code automatically" do
      changeset =
        EmailVerification.create_changeset("user-123", Ecto.UUID.generate(), "test@example.com", "itunes:owner")

      code = Ecto.Changeset.get_field(changeset, :verification_code)

      assert String.length(code) == 6
      assert String.match?(code, ~r/^\d{6}$/)
    end

    test "sets expiration to 30 minutes by default" do
      changeset =
        EmailVerification.create_changeset("user-123", Ecto.UUID.generate(), "test@example.com", "itunes:owner")

      expires_at = Ecto.Changeset.get_field(changeset, :expires_at)
      expected_expires = DateTime.utc_now() |> DateTime.add(30 * 60, :second)
      diff = DateTime.diff(expires_at, expected_expires)

      assert diff >= -5 and diff <= 5
    end

    test "respects custom expiration_minutes option" do
      changeset =
        EmailVerification.create_changeset(
          "user-123",
          Ecto.UUID.generate(),
          "test@example.com",
          "itunes:owner",
          expiration_minutes: 60
        )

      expires_at = Ecto.Changeset.get_field(changeset, :expires_at)
      expected_expires = DateTime.utc_now() |> DateTime.add(60 * 60, :second)
      diff = DateTime.diff(expires_at, expected_expires)

      assert diff >= -5 and diff <= 5
    end
  end

  describe "mark_sent_changeset/1" do
    test "sets status to sent and records time" do
      verification = %EmailVerification{id: Ecto.UUID.generate(), status: "pending"}

      changeset = EmailVerification.mark_sent_changeset(verification)

      assert Ecto.Changeset.get_field(changeset, :status) == "sent"
      assert Ecto.Changeset.get_field(changeset, :sent_at) != nil
    end
  end

  describe "verify_changeset/1" do
    test "sets status to verified and records time" do
      verification = %EmailVerification{id: Ecto.UUID.generate(), status: "sent"}

      changeset = EmailVerification.verify_changeset(verification)

      assert Ecto.Changeset.get_field(changeset, :status) == "verified"
      assert Ecto.Changeset.get_field(changeset, :verified_at) != nil
    end
  end

  describe "increment_attempts_changeset/1" do
    test "increments attempts when under max" do
      verification = %EmailVerification{id: Ecto.UUID.generate(), status: "sent", attempts: 2}

      changeset = EmailVerification.increment_attempts_changeset(verification)

      assert Ecto.Changeset.get_field(changeset, :attempts) == 3
      # Status should not change
      refute Ecto.Changeset.get_change(changeset, :status)
    end

    test "handles nil attempts" do
      verification = %EmailVerification{id: Ecto.UUID.generate(), status: "sent", attempts: nil}

      changeset = EmailVerification.increment_attempts_changeset(verification)

      assert Ecto.Changeset.get_field(changeset, :attempts) == 1
    end

    test "sets status to failed at max attempts" do
      # Max attempts is 5, so at 4 we hit max when incremented
      verification = %EmailVerification{id: Ecto.UUID.generate(), status: "sent", attempts: 4}

      changeset = EmailVerification.increment_attempts_changeset(verification)

      assert Ecto.Changeset.get_field(changeset, :attempts) == 5
      assert Ecto.Changeset.get_field(changeset, :status) == "failed"
    end

    test "sets status to failed when already at max" do
      verification = %EmailVerification{id: Ecto.UUID.generate(), status: "sent", attempts: 5}

      changeset = EmailVerification.increment_attempts_changeset(verification)

      assert Ecto.Changeset.get_field(changeset, :attempts) == 6
      assert Ecto.Changeset.get_field(changeset, :status) == "failed"
    end
  end

  describe "expire_changeset/1" do
    test "sets status to expired" do
      verification = %EmailVerification{id: Ecto.UUID.generate(), status: "pending"}

      changeset = EmailVerification.expire_changeset(verification)

      assert Ecto.Changeset.get_field(changeset, :status) == "expired"
    end
  end

  describe "max_attempts/0" do
    test "returns expected value" do
      assert EmailVerification.max_attempts() == 5
    end
  end

  describe "valid_statuses/0" do
    test "returns expected status list" do
      statuses = EmailVerification.valid_statuses()

      assert "pending" in statuses
      assert "sent" in statuses
      assert "verified" in statuses
      assert "expired" in statuses
      assert "failed" in statuses
      assert length(statuses) == 5
    end
  end

  describe "changeset/2 validations" do
    test "requires user_id" do
      changeset =
        EmailVerification.changeset(%EmailVerification{}, %{
          claim_id: Ecto.UUID.generate(),
          email: "test@example.com",
          email_source: "itunes:owner",
          verification_code: "123456",
          expires_at: DateTime.utc_now()
        })

      refute changeset.valid?
      assert {:user_id, _} = List.keyfind(changeset.errors, :user_id, 0)
    end

    test "requires claim_id" do
      changeset =
        EmailVerification.changeset(%EmailVerification{}, %{
          user_id: "user-123",
          email: "test@example.com",
          email_source: "itunes:owner",
          verification_code: "123456",
          expires_at: DateTime.utc_now()
        })

      refute changeset.valid?
      assert {:claim_id, _} = List.keyfind(changeset.errors, :claim_id, 0)
    end

    test "requires email" do
      changeset =
        EmailVerification.changeset(%EmailVerification{}, %{
          user_id: "user-123",
          claim_id: Ecto.UUID.generate(),
          email_source: "itunes:owner",
          verification_code: "123456",
          expires_at: DateTime.utc_now()
        })

      refute changeset.valid?
      assert {:email, _} = List.keyfind(changeset.errors, :email, 0)
    end

    test "validates email format" do
      changeset =
        EmailVerification.changeset(%EmailVerification{}, %{
          user_id: "user-123",
          claim_id: Ecto.UUID.generate(),
          email: "not-an-email",
          email_source: "itunes:owner",
          verification_code: "123456",
          expires_at: DateTime.utc_now()
        })

      refute changeset.valid?
      assert {:email, _} = List.keyfind(changeset.errors, :email, 0)
    end

    test "accepts valid email" do
      changeset =
        EmailVerification.changeset(%EmailVerification{}, %{
          user_id: "user-123",
          claim_id: Ecto.UUID.generate(),
          email: "podcast@example.com",
          email_source: "itunes:owner",
          verification_code: "123456",
          expires_at: DateTime.utc_now()
        })

      assert changeset.valid?
    end

    test "validates status inclusion" do
      changeset =
        EmailVerification.changeset(%EmailVerification{}, %{
          user_id: "user-123",
          claim_id: Ecto.UUID.generate(),
          email: "test@example.com",
          email_source: "itunes:owner",
          verification_code: "123456",
          expires_at: DateTime.utc_now(),
          status: "invalid_status"
        })

      refute changeset.valid?
      assert {:status, _} = List.keyfind(changeset.errors, :status, 0)
    end

    test "accepts valid statuses" do
      for status <- ~w(pending sent verified expired failed) do
        changeset =
          EmailVerification.changeset(%EmailVerification{}, %{
            user_id: "user-123",
            claim_id: Ecto.UUID.generate(),
            email: "test@example.com",
            email_source: "itunes:owner",
            verification_code: "123456",
            expires_at: DateTime.utc_now(),
            status: status
          })

        assert changeset.valid?, "Expected status '#{status}' to be valid"
      end
    end
  end
end
