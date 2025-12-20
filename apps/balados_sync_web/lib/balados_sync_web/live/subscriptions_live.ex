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
  alias BaladosSyncCore.Dispatcher
  alias BaladosSyncCore.Commands.{CreateCollection, UpdateCollection, DeleteCollection, AddFeedToCollection, RemoveFeedFromCollection}
  alias BaladosSyncProjections.ProjectionsRepo
  alias BaladosSyncProjections.Schemas.Collection
  alias BaladosSyncWeb.Queries
  import Ecto.Query

  @collection_colors [
    {"Blue", "#3b82f6"},
    {"Green", "#22c55e"},
    {"Purple", "#a855f7"},
    {"Red", "#ef4444"},
    {"Yellow", "#eab308"},
    {"Pink", "#ec4899"},
    {"Indigo", "#6366f1"},
    {"Teal", "#14b8a6"},
    {"Orange", "#f97316"},
    {"Gray", "#6b7280"}
  ]

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
      |> assign(:show_collection_modal, false)
      |> assign(:editing_collection, nil)
      |> assign(:collection_form, %{"title" => "", "description" => "", "color" => "#3b82f6"})
      |> assign(:show_delete_confirm, false)
      |> assign(:delete_collection_id, nil)
      |> assign(:manage_feeds_mode, false)
      |> assign(:collection_colors, @collection_colors)

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

  # Collection management events
  def handle_event("open_create_collection", _params, socket) do
    {:noreply,
     socket
     |> assign(:show_collection_modal, true)
     |> assign(:editing_collection, nil)
     |> assign(:collection_form, %{"title" => "", "description" => "", "color" => "#3b82f6"})}
  end

  def handle_event("open_edit_collection", %{"id" => collection_id}, socket) do
    collection = Enum.find(socket.assigns.collections, &(&1.id == collection_id))

    if collection do
      {:noreply,
       socket
       |> assign(:show_collection_modal, true)
       |> assign(:editing_collection, collection)
       |> assign(:collection_form, %{
         "title" => collection.title || "",
         "description" => collection.description || "",
         "color" => collection.color || "#3b82f6"
       })}
    else
      {:noreply, socket}
    end
  end

  def handle_event("close_collection_modal", _params, socket) do
    {:noreply,
     socket
     |> assign(:show_collection_modal, false)
     |> assign(:editing_collection, nil)}
  end

  def handle_event("update_collection_form", %{"field" => field, "value" => value}, socket) do
    form = Map.put(socket.assigns.collection_form, field, value)
    {:noreply, assign(socket, :collection_form, form)}
  end

  def handle_event("save_collection", _params, socket) do
    user_id = socket.assigns.current_user.id
    form = socket.assigns.collection_form

    result =
      if socket.assigns.editing_collection do
        # Update existing collection
        command = %UpdateCollection{
          user_id: user_id,
          collection_id: socket.assigns.editing_collection.id,
          title: form["title"],
          description: form["description"],
          color: form["color"],
          event_infos: %{device_id: "web", device_name: "Web Browser"}
        }
        Dispatcher.dispatch(command)
      else
        # Create new collection
        command = %CreateCollection{
          user_id: user_id,
          title: form["title"],
          description: form["description"],
          color: form["color"],
          is_default: false,
          event_infos: %{device_id: "web", device_name: "Web Browser"}
        }
        Dispatcher.dispatch(command)
      end

    case result do
      :ok ->
        # Reload collections
        collections = get_user_collections(user_id)
        {:noreply,
         socket
         |> assign(:collections, collections)
         |> assign(:show_collection_modal, false)
         |> assign(:editing_collection, nil)
         |> put_flash(:info, if(socket.assigns.editing_collection, do: "Collection updated", else: "Collection created"))}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Error: #{inspect(reason)}")}
    end
  end

  def handle_event("confirm_delete_collection", %{"id" => collection_id}, socket) do
    {:noreply,
     socket
     |> assign(:show_delete_confirm, true)
     |> assign(:delete_collection_id, collection_id)}
  end

  def handle_event("cancel_delete", _params, socket) do
    {:noreply,
     socket
     |> assign(:show_delete_confirm, false)
     |> assign(:delete_collection_id, nil)}
  end

  def handle_event("delete_collection", _params, socket) do
    user_id = socket.assigns.current_user.id
    collection_id = socket.assigns.delete_collection_id

    command = %DeleteCollection{
      user_id: user_id,
      collection_id: collection_id,
      event_infos: %{device_id: "web", device_name: "Web Browser"}
    }

    case Dispatcher.dispatch(command) do
      :ok ->
        collections = get_user_collections(user_id)
        {:noreply,
         socket
         |> assign(:collections, collections)
         |> assign(:show_delete_confirm, false)
         |> assign(:delete_collection_id, nil)
         |> assign(:current_collection, nil)
         |> assign(:subscriptions, socket.assigns.all_subscriptions)
         |> put_flash(:info, "Collection deleted")}

      {:error, :cannot_delete_default_collection} ->
        {:noreply,
         socket
         |> assign(:show_delete_confirm, false)
         |> assign(:delete_collection_id, nil)
         |> put_flash(:error, "Cannot delete the default collection")}

      {:error, reason} ->
        {:noreply,
         socket
         |> assign(:show_delete_confirm, false)
         |> put_flash(:error, "Error: #{inspect(reason)}")}
    end
  end

  def handle_event("toggle_manage_feeds", _params, socket) do
    {:noreply, assign(socket, :manage_feeds_mode, not socket.assigns.manage_feeds_mode)}
  end

  def handle_event("toggle_feed_in_collection", %{"feed" => feed, "collection" => collection_id}, socket) do
    user_id = socket.assigns.current_user.id
    collection = Enum.find(socket.assigns.collections, &(&1.id == collection_id))

    if collection do
      feed_in_collection = Enum.any?(collection.collection_subscriptions, &(&1.rss_source_feed == feed))

      command =
        if feed_in_collection do
          %RemoveFeedFromCollection{
            user_id: user_id,
            collection_id: collection_id,
            rss_source_feed: feed,
            event_infos: %{device_id: "web", device_name: "Web Browser"}
          }
        else
          %AddFeedToCollection{
            user_id: user_id,
            collection_id: collection_id,
            rss_source_feed: feed,
            event_infos: %{device_id: "web", device_name: "Web Browser"}
          }
        end

      case Dispatcher.dispatch(command) do
        :ok ->
          collections = get_user_collections(user_id)
          {:noreply, assign(socket, :collections, collections)}

        {:error, reason} ->
          {:noreply, put_flash(socket, :error, "Error: #{inspect(reason)}")}
      end
    else
      {:noreply, socket}
    end
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
            <!-- Collection badges with edit/delete buttons -->
            <%= for collection <- @collections do %>
              <% is_active = @current_collection && @current_collection.id == collection.id %>
              <% feed_count = length(collection.collection_subscriptions) %>
              <div class="relative group inline-flex items-center">
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
                <!-- Edit/Delete buttons on hover -->
                <div class="hidden group-hover:flex absolute -right-1 -top-1 gap-0.5">
                  <button
                    phx-click="open_edit_collection"
                    phx-value-id={collection.id}
                    class="w-5 h-5 rounded-full bg-white shadow-sm border border-zinc-200 flex items-center justify-center text-zinc-500 hover:text-blue-600 hover:border-blue-300"
                    title="Edit collection"
                  >
                    <svg class="w-3 h-3" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                      <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M15.232 5.232l3.536 3.536m-2.036-5.036a2.5 2.5 0 113.536 3.536L6.5 21.036H3v-3.572L16.732 3.732z" />
                    </svg>
                  </button>
                  <%= if not collection.is_default do %>
                    <button
                      phx-click="confirm_delete_collection"
                      phx-value-id={collection.id}
                      class="w-5 h-5 rounded-full bg-white shadow-sm border border-zinc-200 flex items-center justify-center text-zinc-500 hover:text-red-600 hover:border-red-300"
                      title="Delete collection"
                    >
                      <svg class="w-3 h-3" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12" />
                      </svg>
                    </button>
                  <% end %>
                </div>
              </div>
            <% end %>
            <!-- Add Collection button -->
            <button
              phx-click="open_create_collection"
              class="rounded-full w-8 h-8 flex items-center justify-center bg-zinc-100 text-zinc-500 hover:bg-zinc-200 hover:text-zinc-700 transition-colors"
              title="Create collection"
            >
              <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 4v16m8-8H4" />
              </svg>
            </button>
            <!-- Manage Feeds toggle (when viewing a collection) -->
            <%= if @current_collection do %>
              <button
                phx-click="toggle_manage_feeds"
                class={"ml-2 rounded-lg px-3 py-1.5 text-sm font-medium transition-colors " <>
                  if @manage_feeds_mode do
                    "bg-green-600 text-white"
                  else
                    "bg-zinc-100 text-zinc-600 hover:bg-zinc-200"
                  end}
              >
                <%= if @manage_feeds_mode do %>
                  Done
                <% else %>
                  Manage Feeds
                <% end %>
              </button>
            <% end %>
          </div>
        </div>
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
                class="bg-white shadow rounded-lg overflow-hidden relative"
                data-subscription-feed={sub.rss_source_feed}
              >
                <!-- Manage Feeds Checkbox Overlay -->
                <%= if @manage_feeds_mode && @current_collection do %>
                  <% in_collection = Enum.any?(@current_collection.collection_subscriptions, &(&1.rss_source_feed == sub.rss_source_feed)) %>
                  <button
                    phx-click="toggle_feed_in_collection"
                    phx-value-feed={sub.rss_source_feed}
                    phx-value-collection={@current_collection.id}
                    class={"absolute top-2 right-2 z-10 w-8 h-8 rounded-full flex items-center justify-center transition-all " <>
                      if in_collection do
                        "bg-green-500 text-white"
                      else
                        "bg-white/90 border-2 border-zinc-300 text-zinc-400 hover:border-green-500 hover:text-green-500"
                      end}
                  >
                    <%= if in_collection do %>
                      <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M5 13l4 4L19 7" />
                      </svg>
                    <% else %>
                      <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 4v16m8-8H4" />
                      </svg>
                    <% end %>
                  </button>
                <% end %>
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

    <!-- Collection Modal -->
    <%= if @show_collection_modal do %>
      <div class="fixed inset-0 bg-black/50 flex items-center justify-center z-50" phx-click="close_collection_modal">
        <div class="bg-white rounded-lg shadow-xl w-full max-w-md mx-4" phx-click-away="close_collection_modal">
          <div class="p-6">
            <h2 class="text-xl font-bold text-zinc-900 mb-4">
              <%= if @editing_collection, do: "Edit Collection", else: "Create Collection" %>
            </h2>

            <div class="space-y-4">
              <!-- Title -->
              <div>
                <label class="block text-sm font-medium text-zinc-700 mb-1">Title</label>
                <input
                  type="text"
                  value={@collection_form["title"]}
                  phx-keyup="update_collection_form"
                  phx-value-field="title"
                  class="w-full rounded-lg border border-zinc-300 px-3 py-2 focus:outline-none focus:ring-2 focus:ring-blue-500"
                  placeholder="My Collection"
                  autofocus
                />
              </div>

              <!-- Description -->
              <div>
                <label class="block text-sm font-medium text-zinc-700 mb-1">Description (optional)</label>
                <textarea
                  phx-keyup="update_collection_form"
                  phx-value-field="description"
                  class="w-full rounded-lg border border-zinc-300 px-3 py-2 focus:outline-none focus:ring-2 focus:ring-blue-500"
                  rows="2"
                  placeholder="A brief description..."
                ><%= @collection_form["description"] %></textarea>
              </div>

              <!-- Color -->
              <div>
                <label class="block text-sm font-medium text-zinc-700 mb-2">Color</label>
                <div class="flex flex-wrap gap-2">
                  <%= for {name, color} <- @collection_colors do %>
                    <button
                      type="button"
                      phx-click="update_collection_form"
                      phx-value-field="color"
                      phx-value-value={color}
                      class={"w-8 h-8 rounded-full border-2 transition-all " <>
                        if @collection_form["color"] == color do
                          "border-zinc-900 ring-2 ring-offset-2 ring-zinc-400"
                        else
                          "border-transparent hover:border-zinc-300"
                        end}
                      style={"background-color: #{color}"}
                      title={name}
                    />
                  <% end %>
                </div>
              </div>
            </div>

            <div class="flex justify-end gap-3 mt-6">
              <button
                phx-click="close_collection_modal"
                class="px-4 py-2 text-sm font-medium text-zinc-700 hover:text-zinc-900"
              >
                Cancel
              </button>
              <button
                phx-click="save_collection"
                class="px-4 py-2 text-sm font-medium text-white bg-blue-600 rounded-lg hover:bg-blue-700"
              >
                <%= if @editing_collection, do: "Save Changes", else: "Create" %>
              </button>
            </div>
          </div>
        </div>
      </div>
    <% end %>

    <!-- Delete Confirmation Modal -->
    <%= if @show_delete_confirm do %>
      <div class="fixed inset-0 bg-black/50 flex items-center justify-center z-50">
        <div class="bg-white rounded-lg shadow-xl w-full max-w-sm mx-4 p-6">
          <h2 class="text-lg font-bold text-zinc-900 mb-2">Delete Collection?</h2>
          <p class="text-zinc-600 mb-6">
            This will remove the collection but keep your subscriptions. This action cannot be undone.
          </p>
          <div class="flex justify-end gap-3">
            <button
              phx-click="cancel_delete"
              class="px-4 py-2 text-sm font-medium text-zinc-700 hover:text-zinc-900"
            >
              Cancel
            </button>
            <button
              phx-click="delete_collection"
              class="px-4 py-2 text-sm font-medium text-white bg-red-600 rounded-lg hover:bg-red-700"
            >
              Delete
            </button>
          </div>
        </div>
      </div>
    <% end %>
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
