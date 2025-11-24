defmodule BaladosSyncWeb.AppAuth do
  @moduledoc """
  Handles app authorization logic using JWT tokens.
  Apps present a JWT containing their public key and metadata,
  which is stored in the api_tokens table upon authorization.
  """

  require Logger

  alias BaladosSyncProjections.Repo
  alias BaladosSyncProjections.Schemas.ApiToken
  import Ecto.Query

  @doc """
  Decodes a JWT and verifies it using the public_key inside the JWT claims.

  Expected claims in the token:
  - "app": app details
    - "public_key": PEM-encoded RSA public key
    - "name": Application name
    - "url": Application URL (optional)
    - "image": Application image URL (optional)
  - "jti": Unique token identifier
  - "scopes": Array of requested scopes (optional)

  Returns {:ok, decoded_claims} or {:error, reason}
  """
  def decode_app_token(token) do
    with {:ok, claims} <- Joken.peek_claims(token),
         {:ok, public_key} <- extract_public_key(claims),
         {:ok, verified_claims} <- verify_with_public_key(token, public_key) do
      {:ok, verified_claims}
    else
      {:error, reason} -> {:error, reason}
      _ -> {:error, :invalid_token}
    end
  end

  @doc """
  Authorizes an app by inserting it into the api_tokens table.

  Takes:
  - user_id: The user authorizing the app
  - decoded_token_data: The verified JWT claims

  Returns {:ok, api_token} or {:error, changeset}
  """
  def authorize_app(user_id, decoded_token_data) do
    attrs = %{
      user_id: user_id,
      app_name: decoded_token_data["app"]["name"],
      app_url: decoded_token_data["app"]["url"],
      app_image: decoded_token_data["app"]["image"],
      public_key: decoded_token_data["app"]["public_key"],
      token_jti: decoded_token_data["jti"],
      scopes: decoded_token_data["scopes"] || []
    }

    # Check if this token is already authorized
    case get_token_by_jti(decoded_token_data["jti"]) do
      nil ->
        Logger.debug("Authorizing new app #{attrs.app_name} for user #{user_id}")
        # New authorization
        %ApiToken{}
        |> ApiToken.changeset(attrs)
        |> Repo.insert()

      existing_token when is_nil(existing_token.revoked_at) ->
        # Token already authorized and active
        {:ok, existing_token}

      existing_token ->
        # Token was revoked, reactivate it
        existing_token
        |> Ecto.Changeset.change(
          revoked_at: nil,
          updated_at: DateTime.utc_now() |> DateTime.truncate(:second)
        )
        |> Repo.update()
    end
  end

  @doc """
  Returns all non-revoked api_tokens for a user.
  """
  def get_authorized_apps(user_id) do
    query =
      from(t in ApiToken,
        where: t.user_id == ^user_id and is_nil(t.revoked_at),
        order_by: [desc: t.inserted_at]
      )

    Repo.all(query)
  end

  @doc """
  Revokes an app authorization by setting revoked_at.

  Returns {:ok, api_token} or {:error, :not_found}
  """
  def revoke_app(user_id, token_jti) do
    query =
      from(t in ApiToken,
        where: t.user_id == ^user_id and t.token_jti == ^token_jti and is_nil(t.revoked_at)
      )

    case Repo.one(query) do
      nil ->
        {:error, :not_found}

      token ->
        token
        |> ApiToken.revoke_changeset()
        |> Repo.update()
    end
  end

  @doc """
  Verifies a JWT from an authorized app.

  Checks api_tokens for jti and verifies with stored public_key.
  Returns {:ok, claims} or {:error, reason}
  """
  def verify_app_request(token, expected_user_id \\ nil) do
    with {:ok, claims} <- Joken.peek_claims(token),
         {:ok, api_token} <- get_active_token(claims["jti"]),
         :ok <- verify_user_id(api_token, expected_user_id),
         {:ok, verified_claims} <- verify_with_public_key(token, api_token.public_key) do
      # Update last_used_at asynchronously
      update_last_used(api_token)
      {:ok, verified_claims}
    else
      {:error, reason} -> {:error, reason}
      _ -> {:error, :invalid_token}
    end
  end

  # Private functions

  defp extract_public_key(claims) do
    case claims["app"]["public_key"] do
      nil -> {:error, :missing_public_key}
      public_key -> {:ok, public_key}
    end
  end

  defp verify_with_public_key(token, public_key) do
    try do
      signer = Joken.Signer.create("RS256", %{"pem" => public_key})
      Joken.verify(token, signer)
    rescue
      e ->
        Logger.error("Failed to verify token: #{inspect(e)}")
        {:error, :verification_failed}
    end
  end

  defp get_token_by_jti(jti) do
    query =
      from(t in ApiToken,
        where: t.token_jti == ^jti
      )

    Repo.one(query)
  end

  defp get_active_token(jti) do
    query =
      from(t in ApiToken,
        where: t.token_jti == ^jti and is_nil(t.revoked_at)
      )

    case Repo.one(query) do
      nil -> {:error, :token_not_found}
      token -> {:ok, token}
    end
  end

  defp verify_user_id(_api_token, nil), do: :ok

  defp verify_user_id(api_token, expected_user_id) do
    if api_token.user_id == expected_user_id do
      :ok
    else
      {:error, :user_mismatch}
    end
  end

  defp update_last_used(api_token) do
    Task.start(fn ->
      from(t in ApiToken, where: t.id == ^api_token.id)
      |> Repo.update_all(set: [last_used_at: DateTime.utc_now() |> DateTime.truncate(:second)])
    end)
  end
end
