defmodule BaladosSyncWeb.AppAuthTest do
  use BaladosSyncWeb.ConnCase, async: true

  alias BaladosSyncWeb.AppAuth
  alias BaladosSyncProjections.Repo
  alias BaladosSyncProjections.Schemas.ApiToken

  # Helper to generate a test RSA key pair
  defp generate_test_keypair do
    # Generate a 2048-bit RSA key pair
    private_key = :public_key.generate_key({:rsa, 2048, 65537})

    # Encode private key to PEM
    private_pem =
      :public_key.pem_encode([
        :public_key.pem_entry_encode(:RSAPrivateKey, private_key)
      ])

    # Extract public key and encode to PEM
    public_key = {:RSAPublicKey, elem(private_key, 2), elem(private_key, 3)}

    public_pem =
      :public_key.pem_encode([
        :public_key.pem_entry_encode(:RSAPublicKey, public_key)
      ])

    {private_pem, public_pem}
  end

  # Helper to create a test JWT
  defp create_test_jwt(private_pem, public_pem, claims \\ %{}) do
    default_claims = %{
      "public_key" => public_pem,
      "name" => "Test App",
      "url" => "https://example.com",
      "image" => "https://example.com/icon.png",
      "jti" => "test-jti-#{System.unique_integer()}",
      "scopes" => ["read:subscriptions", "write:subscriptions"]
    }

    all_claims = Map.merge(default_claims, claims)

    signer = Joken.Signer.create("RS256", %{"pem" => private_pem})
    {:ok, token, _claims} = Joken.encode_and_sign(all_claims, signer)

    {token, all_claims}
  end

  describe "decode_app_token/1" do
    test "successfully decodes a valid token" do
      {private_pem, public_pem} = generate_test_keypair()
      {token, expected_claims} = create_test_jwt(private_pem, public_pem)

      assert {:ok, decoded_claims} = AppAuth.decode_app_token(token)
      assert decoded_claims["name"] == expected_claims["name"]
      assert decoded_claims["jti"] == expected_claims["jti"]
      assert decoded_claims["public_key"] == public_pem
    end

    test "returns error for invalid token" do
      assert {:error, _reason} = AppAuth.decode_app_token("invalid-token")
    end

    test "returns error for token without public_key" do
      {private_pem, _public_pem} = generate_test_keypair()

      claims = %{
        "name" => "Test App",
        "jti" => "test-jti"
      }

      signer = Joken.Signer.create("RS256", %{"pem" => private_pem})
      {:ok, token, _claims} = Joken.encode_and_sign(claims, signer)

      assert {:error, :missing_public_key} = AppAuth.decode_app_token(token)
    end
  end

  describe "authorize_app/2" do
    test "creates a new api_token for a user" do
      {private_pem, public_pem} = generate_test_keypair()
      {_token, claims} = create_test_jwt(private_pem, public_pem)

      user_id = Ecto.UUID.generate()

      assert {:ok, api_token} = AppAuth.authorize_app(user_id, claims)
      assert api_token.user_id == user_id
      assert api_token.app_name == claims["name"]
      assert api_token.app_url == claims["url"]
      assert api_token.app_image == claims["image"]
      assert api_token.public_key == public_pem
      assert api_token.token_jti == claims["jti"]
      assert api_token.scopes == claims["scopes"]
      assert is_nil(api_token.revoked_at)
    end

    test "returns existing token if already authorized" do
      {private_pem, public_pem} = generate_test_keypair()
      {_token, claims} = create_test_jwt(private_pem, public_pem)

      user_id = Ecto.UUID.generate()

      {:ok, first_token} = AppAuth.authorize_app(user_id, claims)
      {:ok, second_token} = AppAuth.authorize_app(user_id, claims)

      assert first_token.id == second_token.id
    end

    test "reactivates revoked token" do
      {private_pem, public_pem} = generate_test_keypair()
      {_token, claims} = create_test_jwt(private_pem, public_pem)

      user_id = Ecto.UUID.generate()

      # Create and revoke
      {:ok, token} = AppAuth.authorize_app(user_id, claims)
      {:ok, _revoked} = AppAuth.revoke_app(user_id, token.token_jti)

      # Reauthorize
      {:ok, reactivated} = AppAuth.authorize_app(user_id, claims)
      assert reactivated.id == token.id
      assert is_nil(reactivated.revoked_at)
    end
  end

  describe "get_authorized_apps/1" do
    test "returns all non-revoked apps for a user" do
      user_id = Ecto.UUID.generate()

      # Create two apps
      {private_pem1, public_pem1} = generate_test_keypair()
      {_token1, claims1} = create_test_jwt(private_pem1, public_pem1)

      {private_pem2, public_pem2} = generate_test_keypair()
      {_token2, claims2} = create_test_jwt(private_pem2, public_pem2, %{"name" => "Second App"})

      {:ok, _token1} = AppAuth.authorize_app(user_id, claims1)
      {:ok, token2} = AppAuth.authorize_app(user_id, claims2)

      # Revoke one
      {:ok, _} = AppAuth.revoke_app(user_id, token2.token_jti)

      # Should only return the non-revoked one
      apps = AppAuth.get_authorized_apps(user_id)
      assert length(apps) == 1
      assert hd(apps).app_name == "Test App"
    end

    test "returns empty list for user with no apps" do
      user_id = Ecto.UUID.generate()
      apps = AppAuth.get_authorized_apps(user_id)
      assert apps == []
    end
  end

  describe "revoke_app/2" do
    test "revokes an authorized app" do
      {private_pem, public_pem} = generate_test_keypair()
      {_token, claims} = create_test_jwt(private_pem, public_pem)

      user_id = Ecto.UUID.generate()

      {:ok, token} = AppAuth.authorize_app(user_id, claims)

      assert {:ok, revoked} = AppAuth.revoke_app(user_id, token.token_jti)
      assert revoked.id == token.id
      assert revoked.revoked_at != nil
    end

    test "returns error for non-existent token" do
      user_id = Ecto.UUID.generate()
      assert {:error, :not_found} = AppAuth.revoke_app(user_id, "non-existent-jti")
    end

    test "returns error for already revoked token" do
      {private_pem, public_pem} = generate_test_keypair()
      {_token, claims} = create_test_jwt(private_pem, public_pem)

      user_id = Ecto.UUID.generate()

      {:ok, token} = AppAuth.authorize_app(user_id, claims)
      {:ok, _revoked} = AppAuth.revoke_app(user_id, token.token_jti)

      assert {:error, :not_found} = AppAuth.revoke_app(user_id, token.token_jti)
    end
  end

  describe "verify_app_request/2" do
    test "verifies a valid request from an authorized app" do
      {private_pem, public_pem} = generate_test_keypair()
      jti = "test-jti-#{System.unique_integer()}"

      claims = %{
        "public_key" => public_pem,
        "name" => "Test App",
        "jti" => jti,
        "sub" => "user-123"
      }

      user_id = Ecto.UUID.generate()

      # Authorize the app first
      {:ok, _token} = AppAuth.authorize_app(user_id, claims)

      # Create a request token
      signer = Joken.Signer.create("RS256", %{"pem" => private_pem})
      request_claims = %{"jti" => jti, "sub" => user_id}
      {:ok, request_token, _} = Joken.encode_and_sign(request_claims, signer)

      assert {:ok, verified_claims} = AppAuth.verify_app_request(request_token)
      assert verified_claims["jti"] == jti
    end

    test "returns error for revoked app" do
      {private_pem, public_pem} = generate_test_keypair()
      jti = "test-jti-#{System.unique_integer()}"

      claims = %{
        "public_key" => public_pem,
        "name" => "Test App",
        "jti" => jti
      }

      user_id = Ecto.UUID.generate()

      # Authorize and then revoke
      {:ok, token} = AppAuth.authorize_app(user_id, claims)
      {:ok, _} = AppAuth.revoke_app(user_id, token.token_jti)

      # Try to verify request
      signer = Joken.Signer.create("RS256", %{"pem" => private_pem})
      request_claims = %{"jti" => jti}
      {:ok, request_token, _} = Joken.encode_and_sign(request_claims, signer)

      assert {:error, :token_not_found} = AppAuth.verify_app_request(request_token)
    end
  end
end
