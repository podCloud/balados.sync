defmodule BaladosSyncWeb.SubscriptionControllerTest do
  use BaladosSyncWeb.ConnCase

  alias BaladosSyncCore.Dispatcher
  alias BaladosSyncCore.Commands.Subscribe
  alias BaladosSyncWeb.JwtTestHelper

  setup do
    user_id = Ecto.UUID.generate()

    # Initialize user aggregate with a subscription
    Dispatcher.dispatch(%Subscribe{
      user_id: user_id,
      rss_source_feed: "aHR0cHM6Ly9pbml0LmV4YW1wbGUuY29tL2ZlZWQ",
      rss_source_id: "init-feed",
      subscribed_at: DateTime.utc_now(),
      event_infos: %{}
    })

    Process.sleep(50)

    {:ok, user_id: user_id}
  end

  describe "POST /api/v1/subscriptions - input validation" do
    test "returns 400 when required params are missing", %{conn: conn, user_id: user_id} do
      conn =
        conn
        |> JwtTestHelper.authenticate_conn(user_id, scopes: ["user.subscriptions.write"])
        |> post("/api/v1/subscriptions", %{})

      response = json_response(conn, 400)
      assert response["error"] == "missing_required_parameters"
    end

    test "returns 400 when rss_source_id is missing", %{conn: conn, user_id: user_id} do
      conn =
        conn
        |> JwtTestHelper.authenticate_conn(user_id, scopes: ["user.subscriptions.write"])
        |> post("/api/v1/subscriptions", %{"rss_source_feed" => "dGVzdA"})

      response = json_response(conn, 400)
      assert response["error"] == "missing_required_parameters"
    end
  end
end
