defmodule BaladosSyncWeb.JwtTestHelper do
  @moduledoc """
  Helper module for generating JWT tokens in tests.

  Provides utilities for creating AppTokens and signing JWT requests
  for testing API endpoints that require JWT authentication.
  """

  alias BaladosSyncCore.SystemRepo
  alias BaladosSyncProjections.Schemas.AppToken

  @doc """
  Generates an RSA key pair for testing.

  Returns {private_key_pem, public_key_pem}
  """
  def generate_key_pair do
    private_key = :public_key.generate_key({:rsa, 2048, 65537})
    private_key_pem = :public_key.pem_encode([:public_key.pem_entry_encode(:RSAPrivateKey, private_key)])

    public_key = extract_public_key(private_key)
    public_key_pem = :public_key.pem_encode([:public_key.pem_entry_encode(:SubjectPublicKeyInfo, public_key)])

    {private_key_pem, public_key_pem}
  end

  defp extract_public_key(private_key) do
    {:RSAPrivateKey, _, modulus, public_exponent, _, _, _, _, _, _, _} = private_key
    {:RSAPublicKey, modulus, public_exponent}
  end

  @doc """
  Creates an AppToken in the database for a user.

  Returns {:ok, app_token, private_key_pem} on success.
  """
  def create_app_token(user_id, opts \\ []) do
    {private_key_pem, public_key_pem} = generate_key_pair()

    app_id = Keyword.get(opts, :app_id, "test-app-#{:rand.uniform(100_000)}")
    scopes = Keyword.get(opts, :scopes, ["*"])
    app_name = Keyword.get(opts, :app_name, "Test App")

    attrs = %{
      user_id: user_id,
      app_id: app_id,
      app_name: app_name,
      app_url: "https://test.example.com",
      public_key: public_key_pem,
      scopes: scopes
    }

    case %AppToken{}
         |> AppToken.changeset(attrs)
         |> SystemRepo.insert() do
      {:ok, app_token} -> {:ok, app_token, private_key_pem}
      error -> error
    end
  end

  @doc """
  Generates a signed JWT for API requests.

  The JWT contains:
  - iss: app_id from the AppToken
  - sub: user_id
  - iat: current timestamp
  - exp: expiration (default 1 hour from now)
  """
  def generate_jwt(app_token, private_key_pem, opts \\ []) do
    now = DateTime.utc_now() |> DateTime.to_unix()
    exp = Keyword.get(opts, :exp, now + 3600)

    claims = %{
      "iss" => app_token.app_id,
      "sub" => app_token.user_id,
      "iat" => now,
      "exp" => exp
    }

    # Add any extra claims
    claims = Map.merge(claims, Keyword.get(opts, :extra_claims, %{}))

    signer = Joken.Signer.create("RS256", %{"pem" => private_key_pem})
    {:ok, token, _claims} = Joken.encode_and_sign(claims, signer)

    token
  end

  @doc """
  Creates a connection with JWT authentication.

  Returns a conn with the Authorization header set.
  """
  def authenticate_conn(conn, user_id, opts \\ []) do
    {:ok, app_token, private_key_pem} = create_app_token(user_id, opts)
    jwt = generate_jwt(app_token, private_key_pem, opts)

    Plug.Conn.put_req_header(conn, "authorization", "Bearer #{jwt}")
  end

  @doc """
  Creates all required assigns for JWT auth without going through the plug.

  Useful for directly testing controller logic without JWT verification.
  """
  def assign_jwt_auth(conn, user_id, opts \\ []) do
    app_id = Keyword.get(opts, :app_id, "test-app")
    device_id = Keyword.get(opts, :device_id, "test-device")
    device_name = Keyword.get(opts, :device_name, "Test Device")

    conn
    |> Plug.Conn.assign(:current_user_id, user_id)
    |> Plug.Conn.assign(:app_id, app_id)
    |> Plug.Conn.assign(:device_id, device_id)
    |> Plug.Conn.assign(:device_name, device_name)
  end
end
