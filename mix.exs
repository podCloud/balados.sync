defmodule BaladosSync.Umbrella.MixProject do
  use Mix.Project

  def project do
    [
      apps_path: "apps",
      version: "0.1.0",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      aliases: aliases(),
      name: "Balados Sync",
      source_url: "https://github.com/yourusername/balados-sync",
      homepage_url: "https://balados.sync",
      docs: docs()
    ]
  end

  # Dependencies can be Hex packages:
  #
  #   {:mydep, "~> 0.3.0"}
  #
  # Or git/path repositories:
  #
  #   {:mydep, git: "https://github.com/elixir-lang/mydep.git", tag: "0.1.0"}
  #
  # Type "mix help deps" for more examples and options.
  #
  # Dependencies listed here are available only for this project
  # and cannot be accessed from applications inside the apps/ folder.
  defp deps do
    [
      # Required to run "mix format" on ~H/.heex files from the umbrella root
      {:phoenix_live_view, ">= 0.0.0"},
      {:ex_doc, "~> 0.34", only: :dev, runtime: false}
    ]
  end

  # Aliases are shortcuts or tasks specific to the current project.
  # For example, to install project dependencies and perform other setup tasks, run:
  #
  #     $ mix setup
  #
  # See the documentation for `Mix` for more info on aliases.
  #
  # Aliases listed here are available only for this project
  # and cannot be accessed from applications inside the apps/ folder.
  defp aliases do
    [
      # run `mix setup` in all child apps
      setup: ["cmd mix setup"],
      # Database setup - full initialization
      "db.create": ["system_db.create", "event_store.create -a balados_sync_core"],
      "db.init": ["event_store.init -a balados_sync_core", "system_db.migrate"],
      "db.migrate": ["system_db.migrate"]
    ]
  end

  # ExDoc configuration
  defp docs do
    [
      main: "readme",
      extras: extras(),
      groups_for_extras: groups_for_extras(),
      groups_for_modules: groups_for_modules(),
      before_closing_body_tag: &before_closing_body_tag/1,
      # Filter out internal/test modules
      filter_modules: fn module_name, _ ->
        not String.contains?(module_name, ["Test", "Support"])
      end
    ]
  end

  defp extras do
    [
      "README.md",
      "CLAUDE.md": [title: "Developer Guide"],
      "ORIGINAL_NOTE.md": [title: "Original Specification"]
    ]
  end

  defp groups_for_extras do
    [
      "Getting Started": ~r/README/
    ]
  end

  defp groups_for_modules do
    [
      "Web - Controllers": [
        BaladosSyncWeb.AppAuthController,
        BaladosSyncWeb.SubscriptionController,
        BaladosSyncWeb.PlayStatusController,
        BaladosSyncWeb.PlayController,
        BaladosSyncWeb.EpisodeController,
        BaladosSyncWeb.PrivacyController,
        BaladosSyncWeb.SyncController,
        BaladosSyncWeb.PublicController,
        BaladosSyncWeb.RssProxyController,
        BaladosSyncWeb.RssAggregateController,
        BaladosSyncWeb.PlayGatewayController,
        BaladosSyncWeb.DashboardController,
        BaladosSyncWeb.UserRegistrationController,
        BaladosSyncWeb.UserSessionController
      ],
      "Web - Auth & Plugs": [
        BaladosSyncWeb.AppAuth,
        BaladosSyncWeb.Plugs.JWTAuth,
        BaladosSyncWeb.Plugs.UserAuth
      ],
      "Web - Support": [
        BaladosSyncWeb.RssCache,
        BaladosSyncWeb.Queries,
        BaladosSyncWeb.Accounts,
        BaladosSyncWeb.Endpoint,
        BaladosSyncWeb.Router
      ],
      "Core - Aggregates": [
        BaladosSyncCore.Aggregates.User
      ],
      "Core - Commands": [
        BaladosSyncCore.Commands.Subscribe,
        BaladosSyncCore.Commands.Unsubscribe,
        BaladosSyncCore.Commands.RecordPlay,
        BaladosSyncCore.Commands.UpdatePosition,
        BaladosSyncCore.Commands.SaveEpisode,
        BaladosSyncCore.Commands.ShareEpisode,
        BaladosSyncCore.Commands.ChangePrivacy,
        BaladosSyncCore.Commands.RemoveEvents,
        BaladosSyncCore.Commands.SyncUserData,
        BaladosSyncCore.Commands.Snapshot
      ],
      "Core - Events": [
        BaladosSyncCore.Events.UserSubscribed,
        BaladosSyncCore.Events.UserUnsubscribed,
        BaladosSyncCore.Events.PlayRecorded,
        BaladosSyncCore.Events.PositionUpdated,
        BaladosSyncCore.Events.EpisodeSaved,
        BaladosSyncCore.Events.EpisodeShared,
        BaladosSyncCore.Events.PrivacyChanged,
        BaladosSyncCore.Events.EventsRemoved,
        BaladosSyncCore.Events.UserCheckpoint,
        BaladosSyncCore.Events.PopularityRecalculated
      ],
      "Core - Infrastructure": [
        BaladosSyncCore.Dispatcher,
        BaladosSyncCore.Dispatcher.Router,
        BaladosSyncCore.EventStore,
        BaladosSyncCore.Application
      ],
      "Projections - Schemas": [
        BaladosSyncProjections.Schemas.User,
        BaladosSyncProjections.Schemas.Subscription,
        BaladosSyncProjections.Schemas.PlayStatus,
        BaladosSyncProjections.Schemas.Playlist,
        BaladosSyncProjections.Schemas.PlaylistItem,
        BaladosSyncProjections.Schemas.UserPrivacy,
        BaladosSyncProjections.Schemas.ApiToken,
        BaladosSyncProjections.Schemas.UserToken,
        BaladosSyncProjections.Schemas.PublicEvent,
        BaladosSyncProjections.Schemas.PodcastPopularity,
        BaladosSyncProjections.Schemas.EpisodePopularity
      ],
      "Projections - Projectors": [
        BaladosSyncProjections.Projectors.SubscriptionsProjector,
        BaladosSyncProjections.Projectors.PlayStatusesProjector,
        BaladosSyncProjections.Projectors.PublicEventsProjector,
        BaladosSyncProjections.Projectors.PopularityProjector
      ],
      "Projections - Infrastructure": [
        BaladosSyncProjections.Repo,
        BaladosSyncProjections.Application
      ],
      Jobs: [
        BaladosSyncJobs.SnapshotWorker,
        BaladosSyncJobs.Scheduler
      ]
    ]
  end

  defp before_closing_body_tag(:html) do
    """
    <script>
      // Add custom JavaScript for enhanced documentation experience
      document.addEventListener('DOMContentLoaded', function() {
        // Add badges to module names
        const moduleHeaders = document.querySelectorAll('.content h1');
        moduleHeaders.forEach(header => {
          if (header.textContent.includes('Command')) {
            const badge = document.createElement('span');
            badge.textContent = 'Command';
            badge.className = 'badge badge-command';
            badge.style = 'background: #4CAF50; color: white; padding: 2px 8px; border-radius: 3px; font-size: 12px; margin-left: 10px;';
            header.appendChild(badge);
          } else if (header.textContent.includes('Event')) {
            const badge = document.createElement('span');
            badge.textContent = 'Event';
            badge.className = 'badge badge-event';
            badge.style = 'background: #2196F3; color: white; padding: 2px 8px; border-radius: 3px; font-size: 12px; margin-left: 10px;';
            header.appendChild(badge);
          }
        });
      });
    </script>
    """
  end

  defp before_closing_body_tag(_), do: ""
end
