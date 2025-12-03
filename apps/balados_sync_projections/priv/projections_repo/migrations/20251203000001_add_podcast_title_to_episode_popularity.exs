defmodule BaladosSyncProjections.Migrations.AddPodcastTitleToEpisodePopularity do
  use Ecto.Migration

  def change do
    alter table(:episode_popularity, prefix: "public") do
      add :podcast_title, :string, null: true
    end
  end
end
