defmodule BaladosSyncProjections.SystemRepo.Migrations.AddUserProfileFields do
  use Ecto.Migration

  def change do
    alter table(:users, prefix: "system") do
      add :public_name, :string, size: 100
      add :avatar_url, :string, size: 500
      add :public_profile_enabled, :boolean, default: false, null: false
      add :bio, :string, size: 500
    end

    create index(:users, [:username, :public_profile_enabled],
             prefix: "system",
           )
  end
end
