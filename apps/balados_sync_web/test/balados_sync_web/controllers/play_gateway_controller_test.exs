defmodule BaladosSyncWeb.PlayGatewayControllerTest do
  use BaladosSyncWeb.ConnCase

  alias BaladosSyncCore.SystemRepo
  alias BaladosSyncProjections.Schemas.PlayToken

  @moduletag :play_gateway_controller

  setup do
    user_id = Ecto.UUID.generate()

    # Create a valid PlayToken
    token = PlayToken.generate_token()

    {:ok, _} =
      SystemRepo.insert(%PlayToken{
        user_id: user_id,
        token: token,
        name: "Test Gateway Token",
        expires_at: nil
      })

    feed_url = "https://example.com/feed.xml"
    feed_id = Base.url_encode64(feed_url, padding: false)
    item_id = Base.url_encode64("guid123,https://example.com/ep.mp3", padding: false)

    {:ok, user_id: user_id, token: token, feed_id: feed_id, item_id: item_id}
  end

  describe "GET /play/:user_token/:feed_id/:item_id - authentication" do
    test "returns 401 with invalid token", %{conn: conn, feed_id: feed_id, item_id: item_id} do
      conn = get(conn, "/play/invalid-token-value/#{feed_id}/#{item_id}")

      response = json_response(conn, 401)
      assert response["error"] == "Invalid or revoked token"
    end

    test "returns 401 with revoked token", %{
      conn: conn,
      token: token,
      feed_id: feed_id,
      item_id: item_id
    } do
      # Revoke the token
      import Ecto.Query

      from(t in PlayToken, where: t.token == ^token)
      |> SystemRepo.update_all(set: [revoked_at: DateTime.utc_now()])

      conn = get(conn, "/play/#{token}/#{feed_id}/#{item_id}")

      response = json_response(conn, 401)
      assert response["error"] == "Invalid or revoked token"
    end
  end

  describe "GET /play/:user_token/:feed_id/:item_id - input validation" do
    test "returns 400 with invalid feed base64", %{conn: conn, token: token, item_id: item_id} do
      conn = get(conn, "/play/#{token}/!!!invalid!!!/#{item_id}")

      response = json_response(conn, 400)
      assert response["error"] == "Invalid ID encoding"
    end

    test "returns 400 with invalid item base64", %{conn: conn, token: token, feed_id: feed_id} do
      conn = get(conn, "/play/#{token}/#{feed_id}/!!!invalid!!!")

      response = json_response(conn, 400)
      assert response["error"] == "Invalid ID encoding"
    end
  end

  describe "GET /play/:user_token/:feed_id/:item_id - redirect" do
    test "redirects to enclosure URL with valid params", %{
      conn: conn,
      token: token,
      feed_id: feed_id,
      item_id: item_id
    } do
      conn = get(conn, "/play/#{token}/#{feed_id}/#{item_id}")

      assert conn.status == 302
      location = get_resp_header(conn, "location") |> List.first()
      assert location == "https://example.com/ep.mp3"

      # Verify no-cache headers
      cache_control = get_resp_header(conn, "cache-control") |> List.first()
      assert cache_control =~ "no-cache"
    end
  end
end
