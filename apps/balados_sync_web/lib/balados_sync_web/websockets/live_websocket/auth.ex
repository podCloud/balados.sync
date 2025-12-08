defmodule BaladosSyncWeb.LiveWebSocket.Auth do
  @moduledoc """
  Authentication module for the LiveWebSocket.

  Handles both PlayToken (simple bearer token) and JWT (AppToken) authentication.
  Automatically detects token type and validates accordingly.
  """

  require Logger

  alias BaladosSyncProjections.Schemas.PlayToken
  alias BaladosSyncCore.SystemRepo
  alias BaladosSyncWeb.AppAuth
  import Ecto.Query

  @doc """
  Authenticates a token and returns user_id and token_type.

  Automatically detects whether the token is a PlayToken or JWT token:
  - PlayToken: simple base64 string without dots
  - JWT: contains 3 parts separated by dots

  Returns {:ok, user_id, token_type} or {:error, reason}
  """
  @spec authenticate(String.t()) :: {:ok, String.t(), :play_token | :jwt_token} | {:error, atom()}
  def authenticate(token) when is_binary(token) do
    token_type = detect_token_type(token)
    authenticate_by_type(token, token_type)
  end

  def authenticate(_), do: {:error, :invalid_token}

  # Private functions

  @doc false
  defp detect_token_type(token) do
    case String.split(token, ".") do
      [header, payload, signature]
      when byte_size(header) > 0 and byte_size(payload) > 0 and byte_size(signature) > 0 ->
        # JWT format: three non-empty parts separated by dots
        :jwt_token

      _ ->
        # PlayToken: simple base64 string (0 or 1+ dots are both valid)
        :play_token
    end
  end

  @doc false
  defp authenticate_by_type(token, :play_token) do
    validate_play_token(token)
  end

  defp authenticate_by_type(token, :jwt_token) do
    validate_jwt_token(token)
  end

  @doc false
  defp validate_play_token(token) do
    query =
      from(t in PlayToken,
        where: t.token == ^token and is_nil(t.revoked_at),
        select: {t.user_id, t.expires_at}
      )

    case SystemRepo.one(query) do
      nil ->
        Logger.debug("PlayToken validation failed: invalid or revoked token")
        {:error, :invalid_token}

      {user_id, expires_at} ->
        if token_expired?(expires_at) do
          Logger.debug("PlayToken validation failed: token expired for user #{user_id}")
          {:error, :token_expired}
        else
          Logger.debug("PlayToken validated for user: #{user_id}")
          # Update last_used_at asynchronously
          update_play_token_last_used(token)
          {:ok, user_id, :play_token}
        end
    end
  end

  @doc false
  defp token_expired?(expires_at) do
    case expires_at do
      nil -> false
      _ -> DateTime.compare(expires_at, DateTime.utc_now()) == :lt
    end
  end

  @doc false
  defp validate_jwt_token(token) do
    case AppAuth.verify_app_request(token) do
      {:ok, %{claims: claims}} ->
        user_id = claims["sub"]
        scopes = claims["scopes"] || []

        if has_play_scope?(scopes) do
          Logger.debug("JWT token validated for user: #{user_id} with scopes: #{inspect(scopes)}")
          {:ok, user_id, :jwt_token}
        else
          Logger.debug("JWT token has insufficient scopes: #{inspect(scopes)}")
          {:error, :insufficient_scope}
        end

      {:error, reason} ->
        Logger.debug("JWT token validation failed: #{inspect(reason)}")
        {:error, :invalid_token}
    end
  end

  @doc false
  defp has_play_scope?(scopes) when is_list(scopes) do
    Enum.any?(scopes, fn scope ->
      scope in ["*", "*.write", "user.*", "user.*.write", "user.plays.write"]
    end)
  end

  defp has_play_scope?(_), do: false

  @doc false
  defp update_play_token_last_used(token) do
    Task.start(fn ->
      try do
        from(t in PlayToken, where: t.token == ^token)
        |> SystemRepo.update_all(set: [last_used_at: DateTime.utc_now() |> DateTime.truncate(:second)])

        Logger.debug("PlayToken last_used_at updated successfully for token")
      rescue
        e ->
          Logger.warning("Failed to update PlayToken last_used_at: #{inspect(e)}")
      end
    end)
  end
end
