defmodule BaladosSyncWeb.Router do
  use BaladosSyncWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {BaladosSyncWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  scope "/", BaladosSyncWeb do
    pipe_through :browser

    get "/", PageController, :home
  end

  # Other scopes may use custom stacks.
  # scope "/api", BaladosSyncWeb do
  #   pipe_through :api
  # end

  # Enable LiveDashboard and Swoosh mailbox preview in development
  if Application.compile_env(:balados_sync_web, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: BaladosSyncWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end

  pipeline :api do
    plug :accepts, ["json"]
    plug BaladosSyncWeb.Plugs.JWTAuth
  end

  scope "/api/v1", BaladosSyncWeb do
    pipe_through :api

    # Sync endpoints
    post "/sync", SyncController, :sync

    # Subscription management
    post "/subscriptions", SubscriptionController, :create
    delete "/subscriptions/:feed", SubscriptionController, :delete
    get "/subscriptions", SubscriptionController, :index

    # Play status
    post "/play", PlayController, :record
    put "/play/:item/position", PlayController, :update_position
    get "/play", PlayController, :index

    # Episodes
    post "/episodes/:item/save", EpisodeController, :save
    post "/episodes/:item/share", EpisodeController, :share

    # Privacy
    put "/privacy", PrivacyController, :update
    get "/privacy", PrivacyController, :show

    # Public data (no auth required)
  end

  scope "/api/v1/public", BaladosSyncWeb do
    pipe_through [:accepts, ["json"]]

    get "/trending/podcasts", PublicController, :trending_podcasts
    get "/trending/episodes", PublicController, :trending_episodes
    get "/feed/:feed/popularity", PublicController, :feed_popularity
    get "/episode/:item/popularity", PublicController, :episode_popularity
    get "/timeline", PublicController, :timeline
  end

  # RSS Proxy avec cache
  scope "/api/v1/rss", BaladosSyncWeb do
    pipe_through [:accepts, ["xml", "json"]]

    get "/proxy/:encoded_feed_id", RssProxyController, :proxy
    get "/proxy/:encoded_feed_id/:encoded_episode_id", RssProxyController, :proxy_episode
  end

  # RSS agrégé par user (abonnements et playlists)
  scope "/api/v1/rss/user", BaladosSyncWeb do
    pipe_through [:accepts, ["xml"]]

    get "/:user_token/subscriptions", RssAggregateController, :subscriptions
    get "/:user_token/playlist/:playlist_id", RssAggregateController, :playlist
  end

  # Play gateway (subdomain play.balados.sync)
  scope "/", BaladosSyncWeb, host: "play." do
    pipe_through [:accepts, ["*"]]

    get "/:user_token/:feed_id/:item_id", PlayGatewayController, :play
  end
end
