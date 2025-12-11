defmodule BaladosSyncCore.SystemRepo.Migrations.AddMetadataToCollections do
  use Ecto.Migration

  def change do
    # No changes needed in system repo - collections are event-sourced only
  end
end
