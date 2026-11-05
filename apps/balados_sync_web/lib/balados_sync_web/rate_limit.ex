defmodule BaladosSyncWeb.RateLimit do
  @moduledoc """
  Rate limiter backed by Hammer 7 (ETS, fixed window).

  Started in the web supervision tree; the ETS table is named after this
  module. Callers use `hit/3`: `{:allow, count}` or `{:deny, retry_after_ms}`.
  """

  use Hammer, backend: :ets

  @doc "Drops every bucket. Test helper: never call it in production code."
  @spec reset() :: :ok
  def reset do
    :ets.delete_all_objects(__MODULE__)
    :ok
  end
end
