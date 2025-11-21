defmodule BaladosSyncProjections.Repo.Migrations.CreateUserPrivacy do
  use Ecto.Migration

  def change do
    create table(:user_privacy, primary_key: false, prefix: "users") do
      add :user_id, :string, null: false, primary_key: true

      # Si NULL, privacy globale. Si feed non-null et item null, privacy du feed. Si les deux, privacy de l'item.
      add :rss_source_feed, :text, primary_key: true, default: ""
      add :rss_source_item, :text, primary_key: true, default: ""
      add :privacy, :string, null: false, default: "public"

      timestamps(type: :utc_datetime)
    end

    create index(:user_privacy, [:privacy], prefix: "users")
    create index(:user_privacy, [:user_id], prefix: "users")
    create index(:user_privacy, [:user_id, :rss_source_feed], prefix: "users")

    # Check constraint pour valider les valeurs de privacy
    create constraint(:user_privacy, :valid_privacy,
             prefix: "users",
             check: "privacy IN ('public', 'anonymous', 'private')"
           )
  end
end
