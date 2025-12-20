defmodule BaladosSyncWeb.Router do
  use BaladosSyncWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {BaladosSyncWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug BaladosSyncWeb.Plugs.UserAuth, :fetch_current_user
  end

  pipeline :redirect_if_user_is_authenticated do
    plug BaladosSyncWeb.Plugs.UserAuth, :redirect_if_user_is_authenticated
  end

  pipeline :require_authenticated_user do
    plug BaladosSyncWeb.Plugs.UserAuth, :require_authenticated_user
  end

  pipeline :api_json do
    plug :accepts, ["json"]
    plug :fetch_session
    plug BaladosSyncWeb.Plugs.UserAuth, :fetch_current_user
  end

  # Setup route (accessible même sans users)
  scope "/", BaladosSyncWeb do
    pipe_through :browser

    get "/setup", SetupController, :show
    post "/setup", SetupController, :create
  end

  scope "/", BaladosSyncWeb do
    pipe_through :browser

    get "/", PageController, :home
    get "/app-creator", PageController, :app_creator

    # App authorization (public, but may redirect to login if not authenticated)
    get "/authorize", AppAuthController, :authorize

    # Public discovery pages
    get "/trending/podcasts", PublicController, :trending_podcasts_html
    get "/trending/episodes", PublicController, :trending_episodes_html
    get "/timeline", PublicController, :timeline_html
    get "/podcasts/:feed", PublicController, :feed_page
    get "/episodes/:item", PublicController, :episode_page

    # Subscribe/Unsubscribe actions (authentication checked in controller)
    post "/podcasts/:feed/subscribe", PublicController, :subscribe_to_feed
    delete "/podcasts/:feed/subscribe", PublicController, :unsubscribe_from_feed
  end

  # Privacy check/set endpoints (JSON, session auth, works for both authenticated and unauthenticated)
  scope "/", BaladosSyncWeb do
    pipe_through :api_json

    get "/privacy/check/:feed", WebPrivacyController, :check_privacy
    post "/privacy/set/:feed", WebPrivacyController, :set_privacy
  end

  # Routes for user authentication (public access)
  scope "/users", BaladosSyncWeb do
    pipe_through [:browser, :redirect_if_user_is_authenticated]

    get "/register", UserRegistrationController, :new
    post "/register", UserRegistrationController, :create
    get "/log_in", UserSessionController, :new
    post "/log_in", UserSessionController, :create
  end

  # Routes for authenticated users only
  scope "/", BaladosSyncWeb do
    pipe_through [:browser, :require_authenticated_user]

    get "/dashboard", DashboardController, :index
    delete "/users/log_out", UserSessionController, :delete

    # Web Subscriptions (non-live actions)
    get "/subscriptions/new", WebSubscriptionsController, :new
    post "/subscriptions", WebSubscriptionsController, :create
    get "/subscriptions/export.opml", WebSubscriptionsController, :export_opml

    # Redirect old subscription detail page to public podcast page
    get "/subscriptions/:feed", WebSubscriptionsController, :redirect_to_public

    # Playlists (HTML interface for managing episode playlists)
    get "/playlists", PlaylistsController, :index
    get "/playlists/new", PlaylistsController, :new
    post "/playlists", PlaylistsController, :create
    get "/playlists/:id", PlaylistsController, :show
    get "/playlists/:id/edit", PlaylistsController, :edit
    put "/playlists/:id", PlaylistsController, :update
    delete "/playlists/:id", PlaylistsController, :delete
    post "/playlists/:id/toggle-visibility", PlaylistsController, :toggle_visibility

    # Privacy Manager (HTML interface for managing podcast privacy levels)
    get "/privacy-manager", PrivacyManagerController, :index
    post "/privacy-manager/:feed", PrivacyManagerController, :update_privacy
    delete "/privacy-manager/:feed", PrivacyManagerController, :delete_privacy

    # App authorization confirmation (requires authentication)
    post "/authorize", AppAuthController, :create_authorization

    # App management (HTML interface)
    get "/apps", AppAuthController, :manage_apps
  end

  # LiveView routes for authenticated users
  scope "/", BaladosSyncWeb do
    pipe_through [:browser]

    live_session :authenticated,
      on_mount: [{BaladosSyncWeb.Plugs.UserAuth, :ensure_authenticated}] do
      live "/subscriptions", SubscriptionsLive
    end
  end

  # Admin routes (requires authenticated user with admin role)
  scope "/admin", BaladosSyncWeb do
    pipe_through [:browser, :require_authenticated_user]

    get "/", AdminController, :index
    get "/rss-utility", AdminController, :rss_utility
    post "/rss-utility/generate", AdminController, :generate_rss_link
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

  pipeline :public_api do
    plug :accepts, ["json"]
  end

  pipeline :rss_api do
    plug :accepts, ["xml", "json"]
  end

  pipeline :rss_xml do
    plug :accepts, ["xml"]
  end

  pipeline :play_gateway do
    plug :accepts, ["*"]
  end

  scope "/api/v1", BaladosSyncWeb, host: "sync." do
    # Live WebSocket (with subdomain sync)
    get "/live", LiveWebSocketController, :upgrade
  end

  scope "/api/v1", BaladosSyncWeb do
    pipe_through :api

    # Sync endpoints
    post "/sync", SyncController, :sync

    # Subscription management
    post "/subscriptions", SubscriptionController, :create
    delete "/subscriptions/:feed", SubscriptionController, :delete
    get "/subscriptions", SubscriptionController, :index
    get "/subscriptions/:feed/metadata", SubscriptionController, :metadata

    # Collections management
    get "/collections", CollectionsController, :index
    get "/collections/:id", CollectionsController, :show
    post "/collections", CollectionsController, :create
    patch "/collections/:id", CollectionsController, :update
    delete "/collections/:id", CollectionsController, :delete
    post "/collections/:id/feeds", CollectionsController, :add_feed
    delete "/collections/:id/feeds/:feed_id", CollectionsController, :remove_feed

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

    # App management (JWT authenticated)
    get "/apps", AppAuthController, :index
    delete "/apps/:app_id", AppAuthController, :delete
  end

  scope "/api/v1/public", BaladosSyncWeb do
    pipe_through :public_api

    get "/trending/podcasts", PublicController, :trending_podcasts
    get "/trending/episodes", PublicController, :trending_episodes
    get "/feed/:feed/popularity", PublicController, :feed_popularity
    get "/episode/:item/popularity", PublicController, :episode_popularity
    get "/timeline", PublicController, :timeline
  end

  # RSS Proxy avec cache
  scope "/api/v1/rss", BaladosSyncWeb do
    pipe_through :rss_api

    get "/proxy/:encoded_feed_id", RssProxyController, :proxy
    get "/proxy/:encoded_feed_id/:encoded_episode_id", RssProxyController, :proxy_episode
  end

  # RSS agrégé par user (abonnements, collections et playlists)
  # Note: .xml extension is not supported in dynamic paths by Phoenix,
  # so we use paths without extension. The format is determined by Accept header.
  scope "/rss", BaladosSyncWeb do
    pipe_through :rss_xml

    get "/:user_token/subscriptions", RssAggregateController, :subscriptions
    get "/:user_token/collections/:collection_id", RssAggregateController, :collection
    get "/:user_token/playlists/:playlist_id", RssAggregateController, :playlist
  end

  # Play gateway (subdomain play.balados.sync)
  scope "/", BaladosSyncWeb, host: "play." do
    pipe_through :play_gateway

    get "/:user_token/:feed_id/:item_id", PlayGatewayController, :play
  end

  # Play gateway (path /play/ - alternative for development)
  scope "/play", BaladosSyncWeb do
    pipe_through :play_gateway

    get "/:user_token/:feed_id/:item_id", PlayGatewayController, :play
  end

  # Live WebSocket (path /sync/ - for production alternative and development)
  scope "/sync/api/v1", BaladosSyncWeb do
    get "/live", LiveWebSocketController, :upgrade
  end
end
