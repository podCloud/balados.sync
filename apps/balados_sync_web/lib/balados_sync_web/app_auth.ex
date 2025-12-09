defmodule BaladosSyncWeb.AppAuth do
  @moduledoc """
  Handles app authorization logic using JWT tokens.

  Apps present a JWT containing their public key, app_id (in iss field), and metadata.
  Upon authorization, this information is stored in the app_tokens table.

  ## JWT Structure

  Apps must create JWTs with:
  - `iss` - App ID (mandatory, unique identifier for the app)
  - `app` - App details (name, url, image, public_key)
  - `scopes` - Requested scopes (optional, defaults to [])

  ## Authentication Flow

  1. App creates authorization JWT with its metadata and public key
  2. User authorizes the app via web interface
  3. App creates request JWTs signed with its private key
  4. API verifies JWTs using the stored public key for that app_id
  """

  require Logger

  alias BaladosSyncCore.SystemRepo
  alias BaladosSyncProjections.Schemas.AppToken
  alias BaladosSyncWeb.Scopes
  import Ecto.Query

  @doc """
  Decodes a JWT and verifies it using the public_key inside the JWT claims.

  Expected claims in the token:
  - "iss": App ID (mandatory)
  - "app": app details
    - "public_key": PEM-encoded RSA public key
    - "name": Application name
    - "url": Application URL (optional)
    - "image": Application image URL (optional)
  - "scopes": Array of requested scopes (optional)

  Returns {:ok, decoded_claims} or {:error, reason}
  """
  def decode_app_token(token) do
    with {:ok, claims} <- Joken.peek_claims(token),
         {:ok, _app_id} <- extract_app_id(claims),
         {:ok, public_key} <- extract_public_key(claims),
         {:ok, verified_claims} <- verify_with_public_key(token, public_key) do
      {:ok, verified_claims}
    else
      {:error, reason} -> {:error, reason}
      _ -> {:error, :invalid_token}
    end
  end

  @doc """
  Authorizes an app by inserting or updating it in the app_tokens table.

  Takes:
  - user_id: The user authorizing the app
  - decoded_token_data: The verified JWT claims

  Returns {:ok, app_token} or {:error, changeset}

  If the same app (user_id + app_id combination) is already authorized,
  this updates the scopes and app metadata.
  """
  def authorize_app(user_id, decoded_token_data) do
    app_id = decoded_token_data["iss"]

    attrs = %{
      user_id: user_id,
      app_id: app_id,
      app_name: decoded_token_data["app"]["name"],
      app_url: decoded_token_data["app"]["url"],
      app_image: decoded_token_data["app"]["image"],
      public_key: decoded_token_data["app"]["public_key"],
      scopes: decoded_token_data["scopes"] || []
    }

    # Validate scopes
    case Scopes.validate_scopes(attrs.scopes) do
      {:ok, _} ->
        # Check if this app is already authorized by this user
        case get_token_by_user_and_app(user_id, app_id) do
          nil ->
            Logger.debug("Authorizing new app #{attrs.app_name} (#{app_id}) for user #{user_id}")

            %AppToken{}
            |> AppToken.changeset(attrs)
            |> SystemRepo.insert()

          existing_token when is_nil(existing_token.revoked_at) ->
            Logger.debug(
              "Updating authorization for app #{attrs.app_name} (#{app_id}) for user #{user_id}"
            )

            # Update existing authorization (e.g., new scopes requested)
            existing_token
            |> AppToken.changeset(attrs)
            |> SystemRepo.update()

          existing_token ->
            Logger.debug(
              "Reactivating revoked app #{attrs.app_name} (#{app_id}) for user #{user_id}"
            )

            # Token was revoked, reactivate it
            existing_token
            |> AppToken.changeset(Map.put(attrs, :revoked_at, nil))
            |> SystemRepo.update()
        end

      {:error, invalid_scopes} ->
        {:error, "Invalid scopes: #{Enum.join(invalid_scopes, ", ")}"}
    end
  end

  @doc """
  Returns all non-revoked app_tokens for a user.
  """
  def get_authorized_apps(user_id) do
    query =
      from(t in AppToken,
        where: t.user_id == ^user_id and is_nil(t.revoked_at),
        order_by: [desc: t.inserted_at]
      )

    SystemRepo.all(query)
  end

  @doc """
  Revokes an app authorization by setting revoked_at.

  Returns {:ok, app_token} or {:error, :not_found}
  """
  def revoke_app(user_id, app_id) do
    query =
      from(t in AppToken,
        where: t.user_id == ^user_id and t.app_id == ^app_id and is_nil(t.revoked_at)
      )

    case SystemRepo.one(query) do
      nil ->
        {:error, :not_found}

      token ->
        token
        |> AppToken.revoke_changeset()
        |> SystemRepo.update()
    end
  end

  @doc """
  Verifies a JWT from an authorized app.

  Uses the app_id from the JWT's 'iss' claim to look up the stored public key,
  then verifies the JWT signature.

  Returns {:ok, %{claims: claims, app_token: app_token}} or {:error, reason}
  """
  def verify_app_request(token) do
    with {:ok, claims} <- Joken.peek_claims(token),
         {:ok, app_id} <- extract_app_id(claims),
         {:ok, user_id} <- extract_user_id(claims),
         {:ok, app_token} <- get_active_token(user_id, app_id),
         {:ok, verified_claims} <- verify_with_public_key(token, app_token.public_key) do
      # Update last_used_at asynchronously
      update_last_used(app_token)
      {:ok, %{claims: verified_claims, app_token: app_token}}
    else
      {:error, reason} -> {:error, reason}
      _ -> {:error, :invalid_token}
    end
  end

  @doc """
  Calculates the usage percentage for an app across all users.

  Uses app_id + public_key to identify unique apps.
  Returns a tuple {user_count, percentage, total_users}
  """
  def get_app_usage_stats(app_id, public_key) do
    # Count users who have authorized this app
    app_user_count =
      from(t in AppToken,
        where: t.app_id == ^app_id and t.public_key == ^public_key and is_nil(t.revoked_at),
        select: count(t.user_id, :distinct)
      )
      |> SystemRepo.one()

    # Count total users (distinct user_ids in app_tokens table)
    total_users =
      from(t in AppToken,
        select: count(t.user_id, :distinct)
      )
      |> SystemRepo.one()

    if total_users > 0 do
      percentage = app_user_count / total_users * 100.0
      {app_user_count, percentage, total_users}
    else
      {0, 0.0, 0}
    end
  end

  # Private functions

  defp extract_app_id(claims) do
    case claims["iss"] do
      nil -> {:error, :missing_app_id}
      app_id when is_binary(app_id) -> {:ok, app_id}
      _ -> {:error, :invalid_app_id}
    end
  end

  defp extract_user_id(claims) do
    case claims["sub"] do
      nil -> {:error, :missing_user_id}
      user_id when is_binary(user_id) -> {:ok, user_id}
      _ -> {:error, :invalid_user_id}
    end
  end

  defp extract_public_key(claims) do
    case get_in(claims, ["app", "public_key"]) do
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

  defp get_token_by_user_and_app(user_id, app_id) do
    query =
      from(t in AppToken,
        where: t.user_id == ^user_id and t.app_id == ^app_id
      )

    SystemRepo.one(query)
  end

  defp get_active_token(user_id, app_id) do
    query =
      from(t in AppToken,
        where: t.user_id == ^user_id and t.app_id == ^app_id and is_nil(t.revoked_at)
      )

    case SystemRepo.one(query) do
      nil -> {:error, :token_not_found}
      token -> {:ok, token}
    end
  end

  defp update_last_used(app_token) do
    Task.start(fn ->
      from(t in AppToken, where: t.id == ^app_token.id)
      |> SystemRepo.update_all(
        set: [last_used_at: DateTime.utc_now() |> DateTime.truncate(:second)]
      )
    end)
  end
end
