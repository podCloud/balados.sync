defmodule BaladosSyncWeb.ListeningHistoryLive do
  @moduledoc """
  LiveView for displaying detailed listening history with filters, stats, and pagination.
  """

  use BaladosSyncWeb, :live_view

  alias BaladosSyncWeb.Queries
  import BaladosSyncWeb.Helpers.Pagination, only: [safe_parse_int: 2]

  @per_page 50

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns.current_user
    feed_titles = Queries.get_user_feed_titles(user.id)

    socket =
      socket
      |> assign(:feed_titles, feed_titles)
      |> assign(:page_title, gettext("listening_history.title"))
      |> assign(:stats, nil)
      |> assign(:loading_stats, true)

    if connected?(socket) do
      send(self(), :load_stats)
    end

    {:ok, socket}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    user = socket.assigns.current_user

    page = safe_parse_int(params["page"], 1) |> max(1)
    feed = Map.get(params, "feed", "")
    period = Map.get(params, "period", "")
    status = Map.get(params, "status", "")

    {entries, total} =
      Queries.get_listening_history(user.id,
        page: page,
        per_page: @per_page,
        feed: feed,
        period: period,
        status: status
      )

    total_pages = max(ceil(total / @per_page), 1)

    socket =
      socket
      |> assign(:entries, entries)
      |> assign(:total, total)
      |> assign(:page, page)
      |> assign(:total_pages, total_pages)
      |> assign(:filter_feed, feed)
      |> assign(:filter_period, period)
      |> assign(:filter_status, status)

    {:noreply, socket}
  end

  @impl true
  def handle_event("filter", params, socket) do
    query_params =
      %{}
      |> maybe_put("feed", params["feed"])
      |> maybe_put("period", params["period"])
      |> maybe_put("status", params["status"])

    {:noreply, push_patch(socket, to: ~p"/listening-history?#{query_params}")}
  end

  @impl true
  def handle_info(:load_stats, socket) do
    stats = Queries.get_listening_stats(socket.assigns.current_user.id)

    {:noreply,
     socket
     |> assign(:stats, stats)
     |> assign(:loading_stats, false)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="px-4 py-10 sm:px-6 lg:px-8">
      <div class="mx-auto max-w-5xl">
        <!-- Header -->
        <div class="flex items-center justify-between mb-6">
          <div>
            <h1 class="text-2xl font-bold text-zinc-900">
              <%= gettext("listening_history.title") %>
            </h1>
            <p class="text-sm text-zinc-500 mt-1">
              <%= ngettext(
                "listening_history.count.one",
                "listening_history.count.other",
                @total
              ) %>
            </p>
          </div>
          <div class="flex gap-2">
            <.link
              href={export_url("csv", @filter_feed, @filter_period, @filter_status)}
              class="rounded-lg bg-zinc-100 px-3 py-2 text-sm font-semibold text-zinc-700 hover:bg-zinc-200"
            >
              <%= gettext("listening_history.export_csv") %>
            </.link>
            <.link
              href={export_url("json", @filter_feed, @filter_period, @filter_status)}
              class="rounded-lg bg-zinc-100 px-3 py-2 text-sm font-semibold text-zinc-700 hover:bg-zinc-200"
            >
              <%= gettext("listening_history.export_json") %>
            </.link>
          </div>
        </div>
        <!-- Stats Panel -->
        <h2 class="text-sm font-medium text-zinc-500 mb-2">
          <%= gettext("listening_history.stats.all_time_label") %>
        </h2>
        <div class="grid grid-cols-2 md:grid-cols-5 gap-4 mb-8">
          <div class="bg-white rounded-lg shadow p-4 text-center">
            <div class="text-2xl font-bold text-zinc-900">
              <%= if @loading_stats do %>
                <span class="text-zinc-300">...</span>
              <% else %>
                <%= format_duration(@stats.total_time) %>
              <% end %>
            </div>
            <div class="text-xs text-zinc-500 mt-1">
              <%= gettext("listening_history.stats.total_time") %>
            </div>
          </div>
          <div class="bg-white rounded-lg shadow p-4 text-center">
            <div class="text-2xl font-bold text-zinc-900">
              <%= if @loading_stats, do: "...", else: @stats.total_episodes %>
            </div>
            <div class="text-xs text-zinc-500 mt-1">
              <%= gettext("listening_history.stats.episodes") %>
            </div>
          </div>
          <div class="bg-white rounded-lg shadow p-4 text-center">
            <div class="text-2xl font-bold text-zinc-900">
              <%= if @loading_stats, do: "...", else: @stats.completed_count %>
            </div>
            <div class="text-xs text-zinc-500 mt-1">
              <%= gettext("listening_history.stats.completed") %>
            </div>
          </div>
          <div class="bg-white rounded-lg shadow p-4 text-center">
            <div class="text-2xl font-bold text-zinc-900">
              <%= if @loading_stats do %>
                <span class="text-zinc-300">...</span>
              <% else %>
                <%= @stats.streak_days %>
              <% end %>
            </div>
            <div class="text-xs text-zinc-500 mt-1">
              <%= gettext("listening_history.stats.streak") %>
            </div>
          </div>
          <div class="bg-white rounded-lg shadow p-4 col-span-2 md:col-span-1">
            <div class="text-xs text-zinc-500 mb-2">
              <%= gettext("listening_history.stats.top_podcasts") %>
            </div>
            <%= if @loading_stats do %>
              <div class="text-zinc-300 text-sm">...</div>
            <% else %>
              <%= if Enum.empty?(@stats.top_podcasts) do %>
                <div class="text-zinc-400 text-sm">-</div>
              <% else %>
                <ul class="space-y-1">
                  <%= for {title, count} <- @stats.top_podcasts do %>
                    <li class="text-sm text-zinc-700 truncate" title={title}>
                      <span class="font-medium"><%= count %></span>
                      <span class="text-zinc-500"><%= title %></span>
                    </li>
                  <% end %>
                </ul>
              <% end %>
            <% end %>
          </div>
        </div>
        <!-- Filters -->
        <form phx-change="filter" class="flex flex-wrap gap-3 mb-6">
          <label for="filter-feed" class="sr-only">
            <%= gettext("listening_history.filter.podcast_label") %>
          </label>
          <select
            id="filter-feed"
            name="feed"
            class="rounded-lg border border-zinc-300 px-3 py-2 text-sm focus:ring-2 focus:ring-blue-500"
          >
            <option value=""><%= gettext("listening_history.filter.all_podcasts") %></option>
            <%= for {feed_id, title} <- @feed_titles do %>
              <option value={feed_id} selected={@filter_feed == feed_id}>
                <%= title %>
              </option>
            <% end %>
          </select>

          <label for="filter-period" class="sr-only">
            <%= gettext("listening_history.filter.period_label") %>
          </label>
          <select
            id="filter-period"
            name="period"
            class="rounded-lg border border-zinc-300 px-3 py-2 text-sm focus:ring-2 focus:ring-blue-500"
          >
            <option value="" selected={@filter_period == ""}>
              <%= gettext("listening_history.filter.all_time") %>
            </option>
            <option value="week" selected={@filter_period == "week"}>
              <%= gettext("listening_history.filter.this_week") %>
            </option>
            <option value="month" selected={@filter_period == "month"}>
              <%= gettext("listening_history.filter.this_month") %>
            </option>
            <option value="year" selected={@filter_period == "year"}>
              <%= gettext("listening_history.filter.this_year") %>
            </option>
          </select>

          <label for="filter-status" class="sr-only">
            <%= gettext("listening_history.filter.status_label") %>
          </label>
          <select
            id="filter-status"
            name="status"
            class="rounded-lg border border-zinc-300 px-3 py-2 text-sm focus:ring-2 focus:ring-blue-500"
          >
            <option value="" selected={@filter_status == ""}>
              <%= gettext("listening_history.filter.all_status") %>
            </option>
            <option value="completed" selected={@filter_status == "completed"}>
              <%= gettext("listening_history.filter.completed") %>
            </option>
            <option value="in_progress" selected={@filter_status == "in_progress"}>
              <%= gettext("listening_history.filter.in_progress") %>
            </option>
            <option value="not_started" selected={@filter_status == "not_started"}>
              <%= gettext("listening_history.filter.not_started") %>
            </option>
          </select>
        </form>
        <!-- Episode List -->
        <%= if Enum.empty?(@entries) do %>
          <div class="text-center py-12">
            <p class="text-zinc-600"><%= gettext("listening_history.empty") %></p>
          </div>
        <% else %>
          <div class="space-y-3">
            <%= for entry <- @entries do %>
              <div class="bg-white shadow rounded-lg p-4 flex gap-4 items-center">
                <!-- Cover -->
                <div class="w-16 h-16 rounded-lg bg-zinc-100 flex-shrink-0 overflow-hidden">
                  <%= if cover_url(entry) do %>
                    <img
                      src={cover_url(entry)}
                      alt=""
                      class="w-full h-full object-cover"
                      loading="lazy"
                    />
                  <% else %>
                    <div class="w-full h-full flex items-center justify-center text-zinc-400">
                      <svg class="w-8 h-8" fill="currentColor" viewBox="0 0 24 24">
                        <path d="M12 3v10.55c-.59-.34-1.27-.55-2-.55-2.21 0-4 1.79-4 4s1.79 4 4 4 4-1.79 4-4V7h4V3h-6z" />
                      </svg>
                    </div>
                  <% end %>
                </div>
                <!-- Info -->
                <div class="flex-1 min-w-0">
                  <h3 class="font-medium text-zinc-900 truncate">
                    <%= entry.rss_item_title || gettext("listening_history.unknown_episode") %>
                  </h3>
                  <p class="text-sm text-zinc-500 truncate">
                    <%= entry.rss_feed_title || gettext("listening_history.unknown_podcast") %>
                  </p>
                  <!-- Progress bar -->
                  <div class="mt-2 flex items-center gap-2">
                    <% pct = progress_percent(entry) %>
                    <%= if pct do %>
                      <div class="flex-1 bg-zinc-200 rounded-full h-1.5 max-w-xs">
                        <div
                          class={"rounded-full h-1.5 " <> if entry.played, do: "bg-green-500", else: "bg-blue-500"}
                          style={"width: #{pct}%"}
                        />
                      </div>
                    <% end %>
                    <span class="text-xs text-zinc-500 whitespace-nowrap">
                      <%= format_position(entry) %>
                    </span>
                  </div>
                </div>
                <!-- Status & Time -->
                <div class="flex-shrink-0 text-right">
                  <span class={status_badge_class(entry)}>
                    <%= status_label(entry) %>
                  </span>
                  <p class="text-xs text-zinc-400 mt-1">
                    <%= format_time_ago(entry.updated_at) %>
                  </p>
                </div>
              </div>
            <% end %>
          </div>
          <!-- Pagination -->
          <%= if @total_pages > 1 do %>
            <nav
              class="flex justify-center gap-2 mt-8"
              aria-label={gettext("listening_history.pagination.label")}
            >
              <%= if @page > 1 do %>
                <.link
                  patch={page_url(@page - 1, @filter_feed, @filter_period, @filter_status)}
                  class="rounded-lg bg-zinc-100 px-4 py-2 text-sm font-medium text-zinc-700 hover:bg-zinc-200"
                >
                  <%= gettext("listening_history.pagination.previous") %>
                </.link>
              <% end %>
              <span class="px-4 py-2 text-sm text-zinc-500">
                <%= gettext("listening_history.pagination.page_info",
                  page: @page,
                  total: @total_pages
                ) %>
              </span>
              <%= if @page < @total_pages do %>
                <.link
                  patch={page_url(@page + 1, @filter_feed, @filter_period, @filter_status)}
                  class="rounded-lg bg-zinc-100 px-4 py-2 text-sm font-medium text-zinc-700 hover:bg-zinc-200"
                >
                  <%= gettext("listening_history.pagination.next") %>
                </.link>
              <% end %>
            </nav>
          <% end %>
        <% end %>
      </div>
    </div>
    """
  end

  # Helpers

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, _key, ""), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp page_url(page, feed, period, status) do
    params =
      %{"page" => to_string(page)}
      |> maybe_put("feed", feed)
      |> maybe_put("period", period)
      |> maybe_put("status", status)

    ~p"/listening-history?#{params}"
  end

  defp export_url("csv", feed, period, status) do
    params = build_export_params(feed, period, status)
    ~p"/listening-history/export.csv?#{params}"
  end

  defp export_url("json", feed, period, status) do
    params = build_export_params(feed, period, status)
    ~p"/listening-history/export.json?#{params}"
  end

  defp build_export_params(feed, period, status) do
    %{}
    |> maybe_put("feed", feed)
    |> maybe_put("period", period)
    |> maybe_put("status", status)
  end

  defp cover_url(%{rss_enclosure: %{"cover" => %{"src" => src}}}) when is_binary(src), do: src
  defp cover_url(_), do: nil

  defp progress_percent(%{played: true}), do: 100

  defp progress_percent(%{position: pos, rss_enclosure: %{"duration" => dur}})
       when is_integer(dur) and dur > 0 and pos > 0 do
    min(round(pos / dur * 100), 100)
  end

  defp progress_percent(%{position: pos}) when pos > 0, do: nil
  defp progress_percent(_), do: nil

  defp format_position(%{played: true, rss_enclosure: %{"duration" => dur}})
       when is_integer(dur) do
    format_duration(dur)
  end

  defp format_position(%{position: pos, rss_enclosure: %{"duration" => dur}})
       when is_integer(dur) and dur > 0 do
    "#{format_duration(pos)} / #{format_duration(dur)}"
  end

  defp format_position(%{position: 0}), do: "-"
  defp format_position(%{position: pos}), do: format_duration(pos)

  defp format_duration(0), do: "0:00"

  defp format_duration(seconds) when is_integer(seconds) and seconds >= 0 do
    hours = div(seconds, 3600)
    minutes = div(rem(seconds, 3600), 60)
    secs = rem(seconds, 60)

    if hours > 0 do
      "#{hours}:#{String.pad_leading(to_string(minutes), 2, "0")}:#{String.pad_leading(to_string(secs), 2, "0")}"
    else
      "#{minutes}:#{String.pad_leading(to_string(secs), 2, "0")}"
    end
  end

  defp format_duration(_), do: "0:00"

  defp format_time_ago(nil), do: ""

  # PlayStatus.updated_at is :utc_datetime, so always a DateTime
  defp format_time_ago(%DateTime{} = dt) do
    diff = DateTime.diff(DateTime.utc_now(), dt, :second)

    cond do
      diff < 60 -> gettext("listening_history.time.just_now")
      diff < 3600 -> gettext("listening_history.time.minutes_ago", count: div(diff, 60))
      diff < 86400 -> gettext("listening_history.time.hours_ago", count: div(diff, 3600))
      diff < 604_800 -> gettext("listening_history.time.days_ago", count: div(diff, 86400))
      true -> Date.to_iso8601(DateTime.to_date(dt))
    end
  end

  defp format_time_ago(_), do: ""

  defp status_badge_class(%{played: true}) do
    "inline-block rounded-full px-2 py-0.5 text-xs font-medium bg-green-100 text-green-800"
  end

  defp status_badge_class(%{position: pos}) when pos > 0 do
    "inline-block rounded-full px-2 py-0.5 text-xs font-medium bg-blue-100 text-blue-800"
  end

  defp status_badge_class(_) do
    "inline-block rounded-full px-2 py-0.5 text-xs font-medium bg-zinc-100 text-zinc-600"
  end

  defp status_label(%{played: true}), do: gettext("listening_history.status.completed")

  defp status_label(%{position: pos}) when pos > 0,
    do: gettext("listening_history.status.in_progress")

  defp status_label(_), do: gettext("listening_history.status.not_started")
end
