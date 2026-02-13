defmodule BaladosSyncWeb.AppAuthTest do
  # async: false required because this test accesses the database
  # and Ecto sandbox doesn't work well with async tests and spawned processes
  use BaladosSyncWeb.ConnCase, async: false

  alias BaladosSyncWeb.AppAuth

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

  # Helper to create a test JWT with correct structure for AppAuth
  defp create_test_jwt(private_pem, public_pem, claims \\ %{}) do
    default_claims = %{
      "iss" => "test-app-#{System.unique_integer([:positive])}",
      "app" => %{
        "public_key" => public_pem,
        "name" => "Test App",
        "url" => "https://example.com",
        "image" => "https://example.com/icon.png"
      },
      "scopes" => ["user.subscriptions"]
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
      assert decoded_claims["app"]["name"] == expected_claims["app"]["name"]
      assert decoded_claims["iss"] == expected_claims["iss"]
      assert decoded_claims["app"]["public_key"] == public_pem
    end

    test "returns error for invalid token" do
      assert {:error, _reason} = AppAuth.decode_app_token("invalid-token")
    end

    test "returns error for token without public_key" do
      {private_pem, _public_pem} = generate_test_keypair()

      claims = %{
        "iss" => "test-app",
        "app" => %{
          "name" => "Test App"
        }
      }

      signer = Joken.Signer.create("RS256", %{"pem" => private_pem})
      {:ok, token, _claims} = Joken.encode_and_sign(claims, signer)

      assert {:error, :missing_public_key} = AppAuth.decode_app_token(token)
    end
  end

  describe "authorize_app/2" do
    test "creates a new app_token for a user" do
      {private_pem, public_pem} = generate_test_keypair()
      {_token, claims} = create_test_jwt(private_pem, public_pem)

      user_id = Ecto.UUID.generate()

      assert {:ok, app_token} = AppAuth.authorize_app(user_id, claims)
      assert app_token.user_id == user_id
      assert app_token.app_name == claims["app"]["name"]
      assert app_token.public_key == public_pem
      assert app_token.app_id == claims["iss"]
      assert app_token.scopes == claims["scopes"]
      assert is_nil(app_token.revoked_at)
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
      {:ok, _revoked} = AppAuth.revoke_app(user_id, token.app_id)

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

      {_token2, claims2} =
        create_test_jwt(private_pem2, public_pem2, %{
          "app" => %{
            "public_key" => public_pem2,
            "name" => "Second App",
            "url" => "https://example2.com",
            "image" => "https://example2.com/icon.png"
          }
        })

      {:ok, _token1} = AppAuth.authorize_app(user_id, claims1)
      {:ok, token2} = AppAuth.authorize_app(user_id, claims2)

      # Revoke one
      {:ok, _} = AppAuth.revoke_app(user_id, token2.app_id)

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

      assert {:ok, revoked} = AppAuth.revoke_app(user_id, token.app_id)
      assert revoked.id == token.id
      assert revoked.revoked_at != nil
    end

    test "returns error for non-existent token" do
      user_id = Ecto.UUID.generate()
      assert {:error, :not_found} = AppAuth.revoke_app(user_id, "non-existent-app-id")
    end

    test "returns error for already revoked token" do
      {private_pem, public_pem} = generate_test_keypair()
      {_token, claims} = create_test_jwt(private_pem, public_pem)

      user_id = Ecto.UUID.generate()

      {:ok, token} = AppAuth.authorize_app(user_id, claims)
      {:ok, _revoked} = AppAuth.revoke_app(user_id, token.app_id)

      assert {:error, :not_found} = AppAuth.revoke_app(user_id, token.app_id)
    end
  end

  describe "verify_app_request/1" do
    test "verifies a valid request from an authorized app" do
      {private_pem, public_pem} = generate_test_keypair()
      user_id = Ecto.UUID.generate()
      app_id = "test-app-#{System.unique_integer([:positive])}"

      auth_claims = %{
        "iss" => app_id,
        "app" => %{
          "public_key" => public_pem,
          "name" => "Test App",
          "url" => "https://example.com",
          "image" => "https://example.com/icon.png"
        },
        "scopes" => ["user.subscriptions"]
      }

      # Authorize the app first
      {:ok, _token} = AppAuth.authorize_app(user_id, auth_claims)

      # Create a request token with iss (app_id) and sub (user_id)
      signer = Joken.Signer.create("RS256", %{"pem" => private_pem})
      request_claims = %{"iss" => app_id, "sub" => user_id}
      {:ok, request_token, _} = Joken.encode_and_sign(request_claims, signer)

      assert {:ok, %{claims: verified_claims, app_token: _app_token}} =
               AppAuth.verify_app_request(request_token)

      assert verified_claims["iss"] == app_id
      assert verified_claims["sub"] == user_id
    end

    test "returns error for revoked app" do
      {private_pem, public_pem} = generate_test_keypair()
      user_id = Ecto.UUID.generate()
      app_id = "test-app-#{System.unique_integer([:positive])}"

      auth_claims = %{
        "iss" => app_id,
        "app" => %{
          "public_key" => public_pem,
          "name" => "Test App",
          "url" => "https://example.com",
          "image" => "https://example.com/icon.png"
        },
        "scopes" => ["user.subscriptions"]
      }

      # Authorize and then revoke
      {:ok, token} = AppAuth.authorize_app(user_id, auth_claims)
      {:ok, _} = AppAuth.revoke_app(user_id, token.app_id)

      # Try to verify request
      signer = Joken.Signer.create("RS256", %{"pem" => private_pem})
      request_claims = %{"iss" => app_id, "sub" => user_id}
      {:ok, request_token, _} = Joken.encode_and_sign(request_claims, signer)

      assert {:error, :token_not_found} = AppAuth.verify_app_request(request_token)
    end
  end
end
