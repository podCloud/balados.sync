defmodule BaladosSyncProjections.ProjectionsRepo.Migrations.AddEpisodeLinkToEpisodePopularity do
  use Ecto.Migration

  def change do
    alter table(:episode_popularity, prefix: "public") do
      add :episode_link, :string
    end
  end
end
