defmodule BaladosSyncWeb.RateLimit do
  @moduledoc """
  Rate limiter backed by Hammer 7 (ETS, fixed window).

  Started in the web supervision tree; the ETS table is named after this
  module. Callers use `hit/3`: `{:allow, count}` or `{:deny, retry_after_ms}`.
  """

  use Hammer, backend: :ets

  if Mix.env() == :test do
    @doc "Drops every bucket. Compiled in the test environment only."
    @spec reset() :: :ok
    def reset do
      :ets.delete_all_objects(__MODULE__)
      :ok
    end
  end
end
