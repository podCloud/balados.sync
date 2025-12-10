defmodule BaladosSyncProjections.ProjectionsRepo.Migrations.AddMetadataToCollections do
  use Ecto.Migration

  def change do
    alter table(:collections, prefix: "users") do
      add :description, :text, null: true
      add :color, :text, null: true, default: nil
    end
  end
end
