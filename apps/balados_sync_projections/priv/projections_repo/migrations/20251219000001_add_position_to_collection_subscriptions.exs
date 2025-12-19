defmodule BaladosSyncProjections.Repo.Migrations.AddPositionToCollectionSubscriptions do
  use Ecto.Migration

  def change do
    # Add position column for feed ordering within collections
    alter table(:collection_subscriptions, prefix: "users") do
      add :position, :integer, null: false, default: 0
    end

    # Index for efficient ordering queries
    create index(:collection_subscriptions, [:collection_id, :position], prefix: "users")
  end
end
