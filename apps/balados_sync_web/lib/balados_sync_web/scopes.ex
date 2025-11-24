defmodule BaladosSyncWeb.Scopes do
  @moduledoc """
  Defines and manages API scopes for third-party app authorization.

  Scopes control what operations apps can perform on behalf of users.
  Supports hierarchical scopes with wildcard matching.

  ## Scope Hierarchy

  - `*` - All scopes (full access)
  - `*.read` - All read operations
  - `*.write` - All write operations
  - `user` - User data (includes user.read and user.write)
    - `user.read` - Read user profile
    - `user.write` - Update user profile
  - `user.subscriptions` - Subscription management (includes read and write)
    - `user.subscriptions.read` - List subscriptions
    - `user.subscriptions.write` - Add/remove subscriptions
  - `user.plays` - Play status management (includes read and write)
    - `user.plays.read` - List play statuses and positions
    - `user.plays.write` - Update play positions and mark as played
  - `user.playlists` - Playlist management (includes read and write)
    - `user.playlists.read` - List playlists
    - `user.playlists.write` - Create/update/delete playlists
  - `user.privacy` - Privacy settings (includes read and write)
    - `user.privacy.read` - View privacy settings
    - `user.privacy.write` - Update privacy settings
  - `user.sync` - Full sync access (read and write all user data)

  ## Wildcard Matching

  Granted scopes can use wildcards to match multiple required scopes:
  - `*` matches any scope
  - `*.read` matches any read scope (user.read, user.plays.read, etc.)
  - `user.*` matches all user scopes
  - `user.*.read` matches all user read scopes

  ## Examples

      # Check if granted scopes allow required scope
      iex> Scopes.authorized?(["*"], "user.read")
      true

      iex> Scopes.authorized?(["user.read"], "user.write")
      false

      iex> Scopes.authorized?(["*.read"], "user.plays.read")
      true

      iex> Scopes.authorized?(["user.*"], "user.privacy.write")
      true
  """

  @all_scopes %{
    "*" => "Full access to all data and operations",
    "*.read" => "Read access to all data",
    "*.write" => "Write access to all data",
    "user" => "Full access to user profile",
    "user.read" => "Read user profile information",
    "user.write" => "Update user profile information",
    "user.subscriptions" => "Full access to subscriptions",
    "user.subscriptions.read" => "List podcast subscriptions",
    "user.subscriptions.write" => "Add and remove podcast subscriptions",
    "user.plays" => "Full access to play status and positions",
    "user.plays.read" => "Read playback positions and play status",
    "user.plays.write" => "Update playback positions and mark episodes as played",
    "user.playlists" => "Full access to playlists",
    "user.playlists.read" => "List playlists and their contents",
    "user.playlists.write" => "Create, update, and delete playlists",
    "user.privacy" => "Full access to privacy settings",
    "user.privacy.read" => "View privacy settings",
    "user.privacy.write" => "Update privacy settings",
    "user.sync" => "Full synchronization access (all user data)"
  }

  @doc """
  Returns all defined scopes with their human-readable descriptions.
  """
  def all_scopes, do: @all_scopes

  @doc """
  Returns a list of all scope names.
  """
  def scope_names, do: Map.keys(@all_scopes)

  @doc """
  Returns the human-readable description for a scope.
  """
  def scope_description(scope) do
    Map.get(@all_scopes, scope, scope)
  end

  @doc """
  Checks if the granted scopes authorize the required scope.

  Supports wildcard matching:
  - `*` matches everything
  - `*.read` matches any .read scope
  - `user.*` matches any user.* scope
  - `user.*.read` matches any user.*.read scope

  ## Examples

      iex> Scopes.authorized?(["*"], "user.read")
      true

      iex> Scopes.authorized?(["user.read"], "user.write")
      false

      iex> Scopes.authorized?(["*.read"], "user.plays.read")
      true

      iex> Scopes.authorized?(["user"], "user.read")
      true

      iex> Scopes.authorized?(["user"], "user.privacy.write")
      true

      iex> Scopes.authorized?(["user.*"], "user.privacy.write")
      true
  """
  def authorized?(granted_scopes, required_scope) when is_list(granted_scopes) do
    Enum.any?(granted_scopes, fn granted ->
      scope_matches?(granted, required_scope)
    end)
  end

  @doc """
  Checks if multiple required scopes are all authorized.

  Returns true only if all required scopes are granted.
  """
  def authorized_all?(granted_scopes, required_scopes)
      when is_list(granted_scopes) and is_list(required_scopes) do
    Enum.all?(required_scopes, fn required ->
      authorized?(granted_scopes, required)
    end)
  end

  @doc """
  Checks if any of the required scopes are authorized.

  Returns true if at least one required scope is granted.
  """
  def authorized_any?(granted_scopes, required_scopes)
      when is_list(granted_scopes) and is_list(required_scopes) do
    Enum.any?(required_scopes, fn required ->
      authorized?(granted_scopes, required)
    end)
  end

  @doc """
  Validates that all requested scopes are valid scope names or patterns.

  Returns {:ok, scopes} or {:error, invalid_scopes}
  """
  def validate_scopes(scopes) when is_list(scopes) do
    invalid =
      Enum.reject(scopes, fn scope ->
        valid_scope?(scope)
      end)

    if Enum.empty?(invalid) do
      {:ok, scopes}
    else
      {:error, invalid}
    end
  end

  # Private functions

  # Check if a granted scope matches a required scope
  defp scope_matches?(granted, required) do
    cond do
      # Exact match
      granted == required ->
        true

      # Full wildcard
      granted == "*" ->
        true

      # Parent scope grants child scopes (e.g., "user" grants "user.read")
      String.starts_with?(required, granted <> ".") ->
        true

      # Wildcard pattern matching
      wildcard_matches?(granted, required) ->
        true

      true ->
        false
    end
  end

  # Check if a wildcard pattern matches a required scope
  defp wildcard_matches?(pattern, scope) do
    cond do
      # Pattern: *.read matches user.read, user.plays.read, etc.
      String.starts_with?(pattern, "*.") ->
        suffix = String.replace_prefix(pattern, "*", "")
        String.ends_with?(scope, suffix)

      # Pattern: user.* matches user.read, user.subscriptions, etc.
      String.ends_with?(pattern, ".*") ->
        prefix = String.replace_suffix(pattern, "*", "")
        String.starts_with?(scope, prefix)

      # Pattern: user.*.read matches user.plays.read, user.subscriptions.read, etc.
      String.contains?(pattern, ".*") ->
        complex_wildcard_matches?(pattern, scope)

      true ->
        false
    end
  end

  # Handle complex wildcard patterns like user.*.read
  defp complex_wildcard_matches?(pattern, scope) do
    # Split pattern into parts around .*
    parts = String.split(pattern, ".*", parts: 2)

    case parts do
      [prefix, suffix] ->
        String.starts_with?(scope, prefix) and String.ends_with?(scope, suffix)

      _ ->
        false
    end
  end

  # Check if a scope is a valid scope name or pattern
  defp valid_scope?(scope) do
    cond do
      # Exact match with defined scope
      Map.has_key?(@all_scopes, scope) ->
        true

      # Valid wildcard pattern
      scope == "*" or String.contains?(scope, ".*") or String.ends_with?(scope, ".*") or
          String.starts_with?(scope, "*.") ->
        true

      true ->
        false
    end
  end
end
