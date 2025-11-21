defmodule BaladosSyncWeb.Plugs.JWTAuth do
  import Plug.Conn
  require Logger

  alias BaladosSyncProjections.Repo
  alias BaladosSyncProjections.Schemas.ApiToken
  import Ecto.Query

  def init(opts), do: opts

  def call(conn, _opts) do
    with ["Bearer " <> token] <- get_req_header(conn, "authorization"),
         {:ok, claims} <- verify_token(token),
         {:ok, api_token} <- validate_api_token(claims) do
      # Mettre à jour last_used_at
      update_last_used(api_token)

      conn
      |> assign(:current_user_id, claims["sub"])
      |> assign(:api_token, api_token)
      |> assign(:device_id, claims["device_id"])
      |> assign(:device_name, claims["device_name"])
    else
      _ ->
        conn
        |> put_status(:unauthorized)
        |> Phoenix.Controller.json(%{error: "Unauthorized"})
        |> halt()
    end
  end

  defp verify_token(token) do
    # Décoder le JWT pour récupérer le JTI et récupérer la public key depuis la DB
    case Joken.peek_claims(token) do
      {:ok, claims} ->
        jti = claims["jti"]

        # Récupérer la public key depuis la DB
        case get_public_key(jti) do
          {:ok, public_key} ->
            signer = Joken.Signer.create("RS256", %{"pem" => public_key})
            Joken.verify(token, signer)

          {:error, reason} ->
            {:error, reason}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp get_public_key(jti) do
    query =
      from(t in ApiToken,
        where: t.token_jti == ^jti and is_nil(t.revoked_at),
        select: t.public_key
      )

    case Repo.one(query) do
      nil -> {:error, :token_not_found}
      public_key -> {:ok, public_key}
    end
  end

  defp validate_api_token(claims) do
    jti = claims["jti"]

    query =
      from(t in ApiToken,
        where: t.token_jti == ^jti and is_nil(t.revoked_at)
      )

    case Repo.one(query) do
      nil -> {:error, :invalid_token}
      token -> {:ok, token}
    end
  end

  defp update_last_used(api_token) do
    # Async update pour ne pas bloquer la requête
    Task.start(fn ->
      from(t in ApiToken, where: t.id == ^api_token.id)
      |> Repo.update_all(set: [last_used_at: DateTime.utc_now()])
    end)
  end
end
