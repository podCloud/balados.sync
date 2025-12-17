defmodule BaladosSyncWeb.SubscriptionsLive do
  @moduledoc """
  LiveView for managing podcast subscriptions with collection filtering.

  Displays subscriptions with collection badges that filter the list in real-time.
  The header updates to reflect the current collection selection.
  """

  use BaladosSyncWeb, :live_view

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
    subscriptions = get_subscriptions_with_metadata(user.id)

    {:ok,
     socket
     |> assign(:collections, collections)
     |> assign(:all_subscriptions, subscriptions)
     |> assign(:subscriptions, subscriptions)
     |> assign(:current_collection, nil)
     |> assign(:page_title, "My Subscriptions")}
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
              <%= length(@subscriptions) %> <%= if length(@subscriptions) == 1, do: "subscription", else: "subscriptions" %>
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
                All
                <span class="ml-1 text-xs opacity-70">(<%= length(@all_subscriptions) %>)</span>
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
              <button
                phx-click="filter"
                phx-value-collection=""
                class="text-blue-600 hover:underline"
              >
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
                <div class="aspect-square bg-zinc-100 flex items-center justify-center">
                  <%= if sub.metadata && sub.metadata.cover do %>
                    <img
                      src={sub.metadata.cover.src}
                      alt={sub.metadata.title}
                      class="w-full h-full object-cover"
                    />
                  <% else %>
                    <div class="text-zinc-400">
                      <svg class="w-16 h-16" fill="currentColor" viewBox="0 0 24 24">
                        <path d="M12 2C6.48 2 2 6.48 2 12s4.48 10 10 10 10-4.48 10-10S17.52 2 12 2zm-2 15l-5-5 1.41-1.41L10 14.17l7.59-7.59L19 8l-9 9z"/>
                      </svg>
                    </div>
                  <% end %>
                </div>
                <!-- Content -->
                <div class="p-4">
                  <h3 class="font-semibold text-zinc-900 line-clamp-2">
                    <%= (sub.metadata && sub.metadata.title) || sub.rss_feed_title || "Loading..." %>
                  </h3>
                  <%= if sub.metadata && sub.metadata.description do %>
                    <p class="text-sm text-zinc-600 mt-2 line-clamp-2">
                      <%= sub.metadata.description %>
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
      preload: [collection_subscriptions: :subscription]
    )
    |> ProjectionsRepo.all()
  end

  defp get_subscriptions_with_metadata(user_id) do
    Queries.get_user_subscriptions(user_id)
    |> Enum.map(fn sub ->
      metadata = fetch_metadata_safe(sub.rss_source_feed)
      Map.put(sub, :metadata, metadata)
    end)
  end

  defp fetch_metadata_safe(encoded_feed) do
    with {:ok, feed_url} <- Base.url_decode64(encoded_feed, padding: false),
         {:ok, metadata} <- RssCache.get_feed_metadata(feed_url) do
      metadata
    else
      _ -> nil
    end
  end
end
