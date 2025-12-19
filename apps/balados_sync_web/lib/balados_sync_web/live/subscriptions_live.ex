defmodule BaladosSyncWeb.SubscriptionsLive do
  @moduledoc """
  LiveView for managing podcast subscriptions with collection filtering.

  Displays subscriptions with collection badges that filter the list in real-time.
  The header updates to reflect the current collection selection.

  ## Telemetry Events

  This module emits the following telemetry events:

  - `[:balados_sync, :subscriptions, :metadata, :start]` - When metadata fetch starts
  - `[:balados_sync, :subscriptions, :metadata, :stop]` - When metadata fetch completes
  - `[:balados_sync, :subscriptions, :metadata, :exception]` - When metadata fetch fails
  """

  use BaladosSyncWeb, :live_view

  require Logger

  alias BaladosSyncCore.RssCache
  alias BaladosSyncProjections.ProjectionsRepo
  alias BaladosSyncProjections.Schemas.Collection
  alias BaladosSyncWeb.Queries
  import Ecto.Query

  @impl true
  def mount(_params, _session, socket) do
    # current_user is set by on_mount :ensure_authenticated
    user = socket.assigns.current_user

    collections = get_user_collections(user.id)
    # Load subscriptions without metadata first for fast initial render
    subscriptions = get_subscriptions_without_metadata(user.id)

    socket =
      socket
      |> assign(:collections, collections)
      |> assign(:all_subscriptions, subscriptions)
      |> assign(:subscriptions, subscriptions)
      |> assign(:current_collection, nil)
      |> assign(:page_title, "My Subscriptions")
      |> assign(:loading_metadata, true)

    # Load metadata asynchronously after connected
    if connected?(socket) do
      send(self(), :load_metadata)
    end

    {:ok, socket}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    collection_id = Map.get(params, "collection")

    socket =
      if collection_id do
        case Enum.find(socket.assigns.collections, &(&1.id == collection_id)) do
          nil ->
            # Collection not found, show all
            socket
            |> assign(:current_collection, nil)
            |> assign(:subscriptions, socket.assigns.all_subscriptions)
            |> assign(:page_title, "My Subscriptions")

          collection ->
            # Filter subscriptions by collection
            feed_urls =
              collection.collection_subscriptions
              |> Enum.map(& &1.rss_source_feed)
              |> MapSet.new()

            filtered =
              socket.assigns.all_subscriptions
              |> Enum.filter(&MapSet.member?(feed_urls, &1.rss_source_feed))

            socket
            |> assign(:current_collection, collection)
            |> assign(:subscriptions, filtered)
            |> assign(:page_title, collection.title)
        end
      else
        socket
        |> assign(:current_collection, nil)
        |> assign(:subscriptions, socket.assigns.all_subscriptions)
        |> assign(:page_title, "My Subscriptions")
      end

    {:noreply, socket}
  end

  @impl true
  def handle_event("filter", %{"collection" => ""}, socket) do
    {:noreply, push_patch(socket, to: ~p"/subscriptions")}
  end

  def handle_event("filter", %{"collection" => collection_id}, socket) do
    {:noreply, push_patch(socket, to: ~p"/subscriptions?collection=#{collection_id}")}
  end

  def handle_event("retry_metadata", %{"feed" => encoded_feed}, socket) do
    # Trigger async retry for this feed
    send(self(), {:retry_metadata, encoded_feed})
    {:noreply, socket}
  end

  @impl true
  def handle_info(:load_metadata, socket) do
    # Guard against race condition: if user navigated away or loading was cancelled
    if not socket.assigns.loading_metadata do
      {:noreply, socket}
    else
      # Emit telemetry start event
      start_time = System.monotonic_time()
      total_count = length(socket.assigns.all_subscriptions)

      :telemetry.execute(
        [:balados_sync, :subscriptions, :metadata, :start],
        %{count: total_count},
        %{user_id: socket.assigns.current_user.id}
      )

      # Fetch metadata concurrently for all subscriptions
      # Use ordered: true to maintain list order and zip with originals for timeout handling
      original_subs = socket.assigns.all_subscriptions

      subscriptions_with_metadata =
        original_subs
        |> Task.async_stream(
          fn sub ->
            metadata = fetch_metadata_with_telemetry(sub.rss_source_feed)
            Map.put(sub, :metadata, metadata)
          end,
          max_concurrency: 10,
          timeout: 5_000,
          on_timeout: :kill_task,
          ordered: true
        )
        |> Enum.zip(original_subs)
        |> Enum.map(fn
          {{:ok, sub}, _original} ->
            sub

          {{:exit, reason}, original} ->
            # Log timeout/error with feed identifier
            Logger.warning("Metadata fetch failed for feed",
              feed: truncate_feed_id(original.rss_source_feed),
              reason: inspect(reason)
            )

            # Keep original subscription with error marker instead of dropping it
            Map.put(original, :metadata, :error)
        end)

      # Count successes and failures for telemetry
      {success_count, error_count} =
        Enum.reduce(subscriptions_with_metadata, {0, 0}, fn sub, {s, e} ->
          if sub.metadata == :error or sub.metadata == nil do
            {s, e + 1}
          else
            {s + 1, e}
          end
        end)

      # Emit telemetry stop event
      duration = System.monotonic_time() - start_time

      :telemetry.execute(
        [:balados_sync, :subscriptions, :metadata, :stop],
        %{
          duration: duration,
          total: total_count,
          success: success_count,
          error: error_count
        },
        %{user_id: socket.assigns.current_user.id}
      )

      # Re-apply current filter if any
      filtered =
        if socket.assigns.current_collection do
          feed_urls =
            socket.assigns.current_collection.collection_subscriptions
            |> Enum.map(& &1.rss_source_feed)
            |> MapSet.new()

          Enum.filter(subscriptions_with_metadata, &MapSet.member?(feed_urls, &1.rss_source_feed))
        else
          subscriptions_with_metadata
        end

      {:noreply,
       socket
       |> assign(:all_subscriptions, subscriptions_with_metadata)
       |> assign(:subscriptions, filtered)
       |> assign(:loading_metadata, false)}
    end
  end

  @impl true
  def handle_info({:retry_metadata, encoded_feed}, socket) do
    # Find and retry metadata for a single feed
    updated_subs =
      Enum.map(socket.assigns.all_subscriptions, fn sub ->
        if sub.rss_source_feed == encoded_feed do
          metadata = fetch_metadata_with_telemetry(encoded_feed)
          Map.put(sub, :metadata, metadata)
        else
          sub
        end
      end)

    # Re-apply current filter
    filtered =
      if socket.assigns.current_collection do
        feed_urls =
          socket.assigns.current_collection.collection_subscriptions
          |> Enum.map(& &1.rss_source_feed)
          |> MapSet.new()

        Enum.filter(updated_subs, &MapSet.member?(feed_urls, &1.rss_source_feed))
      else
        updated_subs
      end

    {:noreply,
     socket
     |> assign(:all_subscriptions, updated_subs)
     |> assign(:subscriptions, filtered)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="px-4 py-10 sm:px-6 lg:px-8">
      <div class="mx-auto max-w-7xl">
        <!-- Header -->
        <div class="flex items-center justify-between mb-6">
          <div>
            <h1 class="text-2xl font-bold text-zinc-900 flex items-center gap-3">
              <%= if @current_collection do %>
                <span
                  class="w-4 h-4 rounded-full inline-block"
                  style={"background-color: #{@current_collection.color || "#3b82f6"}"}
                />
                <%= @current_collection.title %>
                <%= if @current_collection.is_default do %>
                  <span class="text-sm font-normal text-zinc-500">(Default)</span>
                <% end %>
              <% else %>
                My Subscriptions
              <% end %>
            </h1>
            <p class="text-sm text-zinc-500 mt-1">
              <%= length(@subscriptions) %> <%= if length(@subscriptions) == 1,
                do: "subscription",
                else: "subscriptions" %>
              <%= if @loading_metadata do %>
                <span class="ml-2 inline-flex items-center">
                  <svg
                    class="animate-spin h-4 w-4 text-zinc-400"
                    xmlns="http://www.w3.org/2000/svg"
                    fill="none"
                    viewBox="0 0 24 24"
                  >
                    <circle
                      class="opacity-25"
                      cx="12"
                      cy="12"
                      r="10"
                      stroke="currentColor"
                      stroke-width="4"
                    >
                    </circle>
                    <path
                      class="opacity-75"
                      fill="currentColor"
                      d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"
                    >
                    </path>
                  </svg>
                  <span class="ml-1">Loading details...</span>
                </span>
              <% end %>
              <%= if @current_collection && @current_collection.description do %>
                <span class="mx-2">&middot;</span>
                <%= @current_collection.description %>
              <% end %>
            </p>
          </div>
          <div class="flex gap-2">
            <.link
              navigate={~p"/subscriptions/new"}
              class="rounded-lg bg-blue-600 px-3 py-2 text-sm font-semibold text-white hover:bg-blue-700"
            >
              Add Subscription
            </.link>
            <.link
              href={~p"/subscriptions/export.opml"}
              class="rounded-lg bg-zinc-100 px-3 py-2 text-sm font-semibold text-zinc-700 hover:bg-zinc-200"
            >
              Export OPML
            </.link>
          </div>
        </div>
        <!-- Collection Badges -->
        <%= if length(@collections) > 0 do %>
          <div class="mb-6">
            <div class="flex flex-wrap gap-2 items-center">
              <!-- All badge -->
              <button
                phx-click="filter"
                phx-value-collection=""
                class={"rounded-full px-4 py-1.5 text-sm font-medium transition-colors cursor-pointer " <>
                  if @current_collection == nil do
                    "bg-blue-600 text-white"
                  else
                    "bg-zinc-100 text-zinc-700 hover:bg-zinc-200"
                  end}
              >
                All <span class="ml-1 text-xs opacity-70">(<%= length(@all_subscriptions) %>)</span>
              </button>
              <!-- Collection badges -->
              <%= for collection <- @collections do %>
                <% is_active = @current_collection && @current_collection.id == collection.id %>
                <% feed_count = length(collection.collection_subscriptions) %>
                <button
                  phx-click="filter"
                  phx-value-collection={collection.id}
                  class={"rounded-full px-4 py-1.5 text-sm font-medium transition-colors cursor-pointer " <>
                    if is_active do
                      "text-white"
                    else
                      "hover:opacity-80"
                    end}
                  style={"background-color: " <>
                    if is_active do
                      collection.color || "#3b82f6"
                    else
                      (collection.color || "#3b82f6") <> "20"
                    end <>
                    if !is_active do
                      "; color: " <> (collection.color || "#3b82f6")
                    else
                      ""
                    end}
                >
                  <%= collection.title %>
                  <span class="ml-1 text-xs opacity-70">(<%= feed_count %>)</span>
                  <%= if collection.is_default do %>
                    <span class="ml-1">*</span>
                  <% end %>
                </button>
              <% end %>
            </div>
          </div>
        <% end %>
        <!-- Subscriptions Grid -->
        <%= if Enum.empty?(@subscriptions) do %>
          <div class="text-center py-12">
            <%= if @current_collection do %>
              <p class="text-zinc-600 mb-4">No subscriptions in this collection.</p>
              <button phx-click="filter" phx-value-collection="" class="text-blue-600 hover:underline">
                View all subscriptions
              </button>
            <% else %>
              <p class="text-zinc-600 mb-4">No subscriptions yet. Add your first podcast!</p>
              <.link
                navigate={~p"/subscriptions/new"}
                class="inline-block rounded-lg bg-blue-600 px-4 py-2 text-sm font-semibold text-white hover:bg-blue-700"
              >
                Get Started
              </.link>
            <% end %>
          </div>
        <% else %>
          <div class="grid grid-cols-1 gap-6 sm:grid-cols-2 lg:grid-cols-3">
            <%= for sub <- @subscriptions do %>
              <div
                class="bg-white shadow rounded-lg overflow-hidden"
                data-subscription-feed={sub.rss_source_feed}
              >
                <!-- Cover Image -->
                <div class="aspect-square bg-zinc-100 flex items-center justify-center relative">
                  <%= if is_map(sub.metadata) && sub.metadata.cover do %>
                    <img
                      src={sub.metadata.cover.src}
                      alt={sub.metadata.title}
                      class="w-full h-full object-cover"
                    />
                  <% else %>
                    <%= if sub.metadata == :error do %>
                      <!-- Error state: red icon with retry button -->
                      <div class="text-center">
                        <div class="text-red-400 mb-2">
                          <svg class="w-16 h-16 mx-auto" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                            <path
                              stroke-linecap="round"
                              stroke-linejoin="round"
                              stroke-width="2"
                              d="M12 9v2m0 4h.01m-6.938 4h13.856c1.54 0 2.502-1.667 1.732-3L13.732 4c-.77-1.333-2.694-1.333-3.464 0L3.34 16c-.77 1.333.192 3 1.732 3z"
                            />
                          </svg>
                        </div>
                        <p class="text-xs text-red-500 mb-2">Failed to load</p>
                        <button
                          phx-click="retry_metadata"
                          phx-value-feed={sub.rss_source_feed}
                          class="text-xs px-3 py-1 bg-red-50 text-red-600 rounded-full hover:bg-red-100 transition-colors"
                        >
                          Retry
                        </button>
                      </div>
                    <% else %>
                      <!-- Loading or no cover state -->
                      <div class="text-zinc-400">
                        <%= if sub.metadata == nil and @loading_metadata do %>
                          <!-- Loading spinner -->
                          <svg
                            class="animate-spin w-12 h-12"
                            xmlns="http://www.w3.org/2000/svg"
                            fill="none"
                            viewBox="0 0 24 24"
                          >
                            <circle
                              class="opacity-25"
                              cx="12"
                              cy="12"
                              r="10"
                              stroke="currentColor"
                              stroke-width="4"
                            >
                            </circle>
                            <path
                              class="opacity-75"
                              fill="currentColor"
                              d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"
                            >
                            </path>
                          </svg>
                        <% else %>
                          <!-- Generic podcast icon -->
                          <svg class="w-16 h-16" fill="currentColor" viewBox="0 0 24 24">
                            <path d="M12 2C6.48 2 2 6.48 2 12s4.48 10 10 10 10-4.48 10-10S17.52 2 12 2zm-2 15l-5-5 1.41-1.41L10 14.17l7.59-7.59L19 8l-9 9z" />
                          </svg>
                        <% end %>
                      </div>
                    <% end %>
                  <% end %>
                </div>
                <!-- Content -->
                <div class="p-4">
                  <h3 class="font-semibold text-zinc-900 line-clamp-2">
                    <%= cond do %>
                      <% is_map(sub.metadata) && sub.metadata.title -> %>
                        <%= sub.metadata.title %>
                      <% sub.rss_feed_title -> %>
                        <%= sub.rss_feed_title %>
                      <% sub.metadata == :error -> %>
                        <span class="text-red-600">Unable to load</span>
                      <% true -> %>
                        Loading...
                    <% end %>
                  </h3>
                  <%= if is_map(sub.metadata) && sub.metadata.description do %>
                    <p class="text-sm text-zinc-600 mt-2 line-clamp-2">
                      <%= sub.metadata.description %>
                    </p>
                  <% end %>
                  <%= if sub.metadata == :error do %>
                    <p class="text-xs text-red-500 mt-2">
                      Could not fetch podcast details. The feed may be temporarily unavailable.
                    </p>
                  <% end %>

                  <div class="mt-4">
                    <.link
                      navigate={~p"/podcasts/#{sub.rss_source_feed}"}
                      class="block w-full rounded-lg bg-blue-600 px-3 py-2 text-center text-sm font-semibold text-white hover:bg-blue-700"
                    >
                      View Details
                    </.link>
                  </div>
                </div>
              </div>
            <% end %>
          </div>
        <% end %>
      </div>
    </div>
    """
  end

  # Private helpers

  defp get_user_collections(user_id) do
    from(c in Collection,
      where: c.user_id == ^user_id,
      where: is_nil(c.deleted_at),
      order_by: [desc: c.is_default, asc: c.title],
      preload: [:collection_subscriptions]
    )
    |> ProjectionsRepo.all()
  end

  defp get_subscriptions_without_metadata(user_id) do
    Queries.get_user_subscriptions(user_id)
    |> Enum.map(fn sub ->
      Map.put(sub, :metadata, nil)
    end)
  end

  defp fetch_metadata_with_telemetry(encoded_feed) do
    start_time = System.monotonic_time()

    result =
      with {:ok, feed_url} <- Base.url_decode64(encoded_feed, padding: false),
           {:ok, metadata} when is_map(metadata) <- RssCache.get_feed_metadata(feed_url) do
        {:ok, metadata}
      else
        {:error, reason} ->
          {:error, reason}

        :error ->
          {:error, :invalid_base64}

        # Invalid metadata (not a map) from cache - treat as fetch failure
        {:ok, _invalid} ->
          {:error, :invalid_metadata}
      end

    duration = System.monotonic_time() - start_time
    feed_id = truncate_feed_id(encoded_feed)

    case result do
      {:ok, metadata} ->
        :telemetry.execute(
          [:balados_sync, :subscriptions, :metadata, :fetch],
          %{duration: duration, success: true},
          %{feed: feed_id}
        )

        metadata

      {:error, reason} ->
        Logger.warning("Metadata fetch failed",
          feed: feed_id,
          reason: inspect(reason)
        )

        :telemetry.execute(
          [:balados_sync, :subscriptions, :metadata, :fetch],
          %{duration: duration, success: false},
          %{feed: feed_id, error: reason}
        )

        :error
    end
  end

  # Truncate feed ID for logging (first 16 chars of base64-encoded URL)
  defp truncate_feed_id(encoded_feed) when is_binary(encoded_feed) do
    if String.length(encoded_feed) > 16 do
      String.slice(encoded_feed, 0, 16) <> "..."
    else
      encoded_feed
    end
  end

  defp truncate_feed_id(_), do: "unknown"
end
