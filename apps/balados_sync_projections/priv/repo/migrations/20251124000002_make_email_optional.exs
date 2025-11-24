defmodule BaladosSyncProjections.Repo.Migrations.MakeEmailOptional do
  use Ecto.Migration

  def change do
    alter table(:users, prefix: "users") do
      modify :email, :string, null: true
    end
  end
end
