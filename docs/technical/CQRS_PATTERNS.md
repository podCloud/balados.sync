# Patterns CQRS/Event Sourcing - Balados Sync

Ce document explique les patterns CQRS/Event Sourcing utilisés dans Balados Sync, avec des exemples concrets.

## 📚 Table des Matières

- [Introduction](#introduction)
- [Event Sourcing Fundamentals](#event-sourcing-fundamentals)
- [CQRS Pattern](#cqrs-pattern)
- [Aggregate Pattern](#aggregate-pattern)
- [Projection Pattern](#projection-pattern)
- [Checkpoint Pattern](#checkpoint-pattern)
- [Exemples Complets](#exemples-complets)
- [Best Practices](#best-practices)
- [Common Pitfalls](#common-pitfalls)

---

## Introduction

### Qu'est-ce que CQRS ?

**CQRS** (Command Query Responsibility Segregation) sépare les opérations de :
- **Write** (Commands) : Intentions de modifier l'état
- **Read** (Queries) : Récupération de données

### Qu'est-ce que Event Sourcing ?

**Event Sourcing** stocke l'état comme une séquence d'événements immuables plutôt qu'un état courant.

### Pourquoi cette Architecture ?

✅ **Avantages** :
- **Audit trail complet** : Historique de toutes les actions
- **Temporal queries** : État à n'importe quel moment
- **Event-driven** : Facile d'ajouter de nouveaux listeners
- **Scalabilité** : Write et read séparés
- **Debugging** : Replay des events pour reproduire bugs

⚠️ **Inconvénients** :
- **Complexité** : Courbe d'apprentissage
- **Eventual consistency** : Projections async
- **Storage** : Events s'accumulent (nécessite checkpoints)

---

## Event Sourcing Fundamentals

### Événements Immuables

```elixir
# ❌ JAMAIS modifier un event existé
%UserSubscribed{id: 1, feed: "old"}
→ Update to %UserSubscribed{id: 1, feed: "new"}  # ❌ NON

# ✅ Émettre un nouvel event
%UserSubscribed{feed: "old"}
→ %UserUnsubscribed{feed: "old"}  # ✅ OUI
→ %UserSubscribed{feed: "new"}    # ✅ OUI
```

### Event Store

L'Event Store est la **source de vérité** :

```
Stream: user-user_123
┌─────────────────────────────────────────┐
│ Event 1: UserSubscribed                 │
│   feed: "podcast A"                     │
│   timestamp: 2025-01-01 10:00           │
├─────────────────────────────────────────┤
│ Event 2: PlayRecorded                   │
│   item: "episode 1"                     │
│   timestamp: 2025-01-01 11:00           │
├─────────────────────────────────────────┤
│ Event 3: PositionUpdated                │
│   item: "episode 1"                     │
│   position: 1234                        │
│   timestamp: 2025-01-01 11:15           │
└─────────────────────────────────────────┘
```

### Rebuilding State

L'état actuel = replay de tous les events :

```elixir
def rebuild_aggregate(stream_id) do
  events = EventStore.read_stream_forward(stream_id)

  Enum.reduce(events, %Subscription{}, fn event, state ->
    Subscription.apply(state, event)
  end)
end
```

---

## CQRS Pattern

### Command Side (Write)

#### 1. Command

Intent de l'utilisateur :

```elixir
defmodule BaladosSyncCore.Commands.Subscribe do
  @enforce_keys [:user_id, :rss_source_feed, :device_id, :device_name]
  defstruct [
    :user_id,
    :rss_source_feed,
    :rss_source_id,
    :rss_feed_title,
    :device_id,
    :device_name,
    :event_infos
  ]
end
```

**Caractéristiques** :
- Nommée au **présent impératif** (Subscribe, not Subscribed)
- Contient toutes les **données nécessaires** pour la décision
- **Immutable** struct

#### 2. Handler (execute/2)

Décide quel(s) event(s) émettre :

```elixir
def execute(%Subscription{} = state, %Subscribe{} = cmd) do
  # Validation
  cond do
    already_subscribed?(state, cmd.rss_source_feed) ->
      {:error, :already_subscribed}

    true ->
      # Retourner l'event à émettre
      %UserSubscribed{
        user_id: cmd.user_id,
        rss_source_feed: cmd.rss_source_feed,
        rss_source_id: cmd.rss_source_id,
        rss_feed_title: cmd.rss_feed_title,
        subscribed_at: DateTime.utc_now(),
        device_id: cmd.device_id,
        device_name: cmd.device_name,
        event_infos: cmd.event_infos
      }
  end
end
```

**Principes** :
- **Pure function** : même input = même output
- **No side effects** : pas d'I/O, pas de queries
- **Validation** : vérifier les règles métier
- **Return event(s)** : ou `{:error, reason}`

#### 3. Event

Fait immuable :

```elixir
defmodule BaladosSyncCore.Events.UserSubscribed do
  @derive Jason.Encoder
  defstruct [
    :user_id,
    :rss_source_feed,
    :rss_source_id,
    :rss_feed_title,
    :subscribed_at,
    :device_id,
    :device_name,
    :event_infos
  ]
end
```

**Caractéristiques** :
- Nommée au **passé** (Subscribed, not Subscribe)
- Contient **toutes les données** de l'événement
- **Immutable** struct
- **Serializable** (JSON)

#### 4. State Application (apply/2)

Met à jour l'état de l'aggregate :

```elixir
def apply(%Subscription{} = state, %UserSubscribed{} = event) do
  subscription = %{
    feed: event.rss_source_feed,
    subscribed_at: event.subscribed_at,
    unsubscribed_at: nil
  }

  subscriptions = Map.put(user.subscriptions, event.rss_source_feed, subscription)

  %{user | subscriptions: subscriptions}
end
```

**Principes** :
- **Pure function**
- **No validation** : l'event est un fait, pas de refus possible
- **Update state** : retourner le nouvel état

### Query Side (Read)

#### 1. Projection (Read Model)

Schema Ecto pour queries rapides :

```elixir
defmodule BaladosSyncProjections.Schemas.Subscription do
  use Ecto.Schema

  @primary_key {:id, :binary_id, autogenerate: true}
  schema "subscriptions" do
    field :user_id, :string
    field :rss_source_feed, :string
    field :rss_source_id, :string
    field :rss_feed_title, :string
    field :subscribed_at, :utc_datetime
    field :unsubscribed_at, :utc_datetime

    timestamps(type: :utc_datetime)
  end
end
```

#### 2. Projector (Event Listener)

Écoute les events et met à jour les projections :

```elixir
defmodule BaladosSyncProjections.Projectors.SubscriptionProjector do
  use Commanded.Projections.Ecto,
    application: BaladosSyncCore.Application,
    repo: BaladosSyncProjections.Repo,
    name: "SubscriptionProjector"

  alias BaladosSyncCore.Events.{UserSubscribed, UserUnsubscribed}
  alias BaladosSyncProjections.Schemas.Subscription

  project %UserSubscribed{} = event, _metadata, fn multi ->
    Ecto.Multi.insert(
      multi,
      :subscription,
      %Subscription{
        user_id: event.user_id,
        rss_source_feed: event.rss_source_feed,
        rss_source_id: event.rss_source_id,
        rss_feed_title: event.rss_feed_title,
        subscribed_at: event.subscribed_at
      },
      on_conflict: {:replace, [:subscribed_at, :updated_at]},
      conflict_target: [:user_id, :rss_source_feed]
    )
  end

  project %UserUnsubscribed{} = event, _metadata, fn multi ->
    Ecto.Multi.update_all(
      multi,
      :subscription,
      from(s in Subscription,
        where: s.user_id == ^event.user_id,
        where: s.rss_source_feed == ^event.rss_source_feed
      ),
      set: [unsubscribed_at: event.unsubscribed_at]
    )
  end
end
```

#### 3. Query

Simple query Ecto :

```elixir
def list_subscriptions(user_id) do
  from(s in Subscription,
    where: s.user_id == ^user_id,
    where: is_nil(s.unsubscribed_at) or s.subscribed_at > s.unsubscribed_at
  )
  |> Repo.all()
end
```

---

## Aggregate Pattern

### Responsabilités de l'Aggregate

1. **Encapsuler** la logique métier
2. **Maintenir** l'invariant (règles métier)
3. **Décider** quels events émettre
4. **Reconstruire** son état depuis les events

### Structure (Bounded Contexts)

Le domaine est séparé en 4 aggregates par bounded context :

```elixir
# Subscription aggregate — subscriptions, privacy, sharing
defmodule BaladosSyncCore.Aggregates.Subscription do
  defstruct [:user_id, :privacy, :subscriptions]

  def execute(%__MODULE__{}, %Subscribe{} = cmd), do: # ...
  def execute(%__MODULE__{}, %Unsubscribe{} = cmd), do: # ...
  def execute(%__MODULE__{}, %ChangePrivacy{} = cmd), do: # ...

  def apply(%__MODULE__{}, %UserSubscribed{} = event), do: # ...
  def apply(%__MODULE__{}, %UserUnsubscribed{} = event), do: # ...
end

# PlayTracking aggregate — play positions
defmodule BaladosSyncCore.Aggregates.PlayTracking do
  defstruct [:user_id, :play_statuses]

  def execute(%__MODULE__{}, %RecordPlay{} = cmd), do: # ...
  def execute(%__MODULE__{}, %UpdatePosition{} = cmd), do: # ...

  def apply(%__MODULE__{}, %PlayRecorded{} = event), do: # ...
end

# Playlist aggregate — playlists and episodes
defmodule BaladosSyncCore.Aggregates.Playlist do
  defstruct [:user_id, :playlists]
  # ...
end

# Collection aggregate — feed organization
defmodule BaladosSyncCore.Aggregates.Collection do
  defstruct [:user_id, :collections]
  # ...
end
```

### Aggregate Identity & Stream Prefixes

Chaque aggregate a son propre **préfixe de stream** pour éviter les collisions :

```elixir
# Dans Dispatcher.Router
identify Subscription,  by: :user_id, prefix: "subscription-"
identify PlayTracking,  by: :user_id, prefix: "play_tracking-"
identify Playlist,      by: :user_id, prefix: "playlist-"
identify Collection,    by: :user_id, prefix: "collection-"

# Command Subscribe avec user_id = "abc123"
# → Routée vers stream "subscription-abc123"
#
# Command RecordPlay avec user_id = "abc123"
# → Routée vers stream "play_tracking-abc123"
```

### Cross-Aggregate Validation (Middleware)

Quand un aggregate doit valider un état dans un autre aggregate, on utilise
un **middleware** qui query les projections (read model) :

```elixir
# ValidateSubscription middleware
# Vérifie que le feed est abonné avant AddFeedToCollection
defmodule BaladosSyncCore.Middleware.ValidateSubscription do
  def before_dispatch(%Pipeline{command: %AddFeedToCollection{}} = pipeline) do
    # Query la projection subscriptions
    case repo.one(query, prefix: "users") do
      nil -> pipeline |> respond({:error, :feed_not_subscribed}) |> halt()
      _id -> pipeline
    end
  end
  def before_dispatch(pipeline), do: pipeline  # passthrough for other commands
end
```

### Multiple Events

Un command peut émettre plusieurs events :

```elixir
def execute(%Subscription{}, %SomeCommand{} = cmd) do
  # Retourner une liste d'events
  [
    %UserSubscribed{...},
    %PlayRecorded{...},
    %PositionUpdated{...}
  ]
end
```

### Business Rules

L'aggregate vérifie les **invariants** :

```elixir
def execute(%Playlist{} = state, %DeletePlaylist{} = cmd) do
  playlist = (state.playlists || %{})[cmd.playlist_id]

  cond do
    is_nil(playlist) ->
      {:error, :playlist_not_found}

    playlist.deleted_at != nil ->
      {:error, :playlist_already_deleted}

    true ->
      %PlaylistDeleted{
        user_id: cmd.user_id,
        playlist_id: cmd.playlist_id,
        deleted_at: DateTime.utc_now()
      }
  end
end
```

---

## Projection Pattern

### Pourquoi des Projections ?

Les projections sont des **vues dénormalisées** optimisées pour les queries.

**Sans projections** :
```
GET /subscriptions
→ Charger aggregate (replay tous les events)
→ Filtrer les subscriptions actives
→ Format JSON
⏱️ LENT pour des milliers d'events
```

**Avec projections** :
```
GET /subscriptions
→ SELECT * FROM subscriptions WHERE user_id = ? AND unsubscribed_at IS NULL
⏱️ RAPIDE (index PostgreSQL)
```

### Types de Projections

#### 1. User-Specific Projection

Données privées d'un utilisateur :

```elixir
# Projection : subscriptions
# Events : UserSubscribed, UserUnsubscribed
# Usage : Liste des abonnements de l'user
```

#### 2. Public/Anonymous Projection

Données publiques pour statistiques :

```elixir
# Projection : public_events
# Events : Tous events (filtrés par privacy)
# Usage : Popularité, découverte
```

#### 3. Aggregate Projection

Calculs agrégés :

```elixir
# Projection : podcast_popularity
# Events : UserSubscribed, PlayRecorded, ...
# Usage : Classement des podcasts populaires
```

### Eventual Consistency

Les projections sont **éventuellement cohérentes** :

```
t0 : POST /subscriptions (command)
t1 : Event persisté dans Event Store
t2 : Projector traite l'event (async)
t3 : Projection mise à jour
t4 : GET /subscriptions (query) ← voit le changement
```

**Délai** : Généralement quelques millisecondes, peut être plus si charge élevée.

### Rebuilding Projections

Si une projection est corrompue :

```bash
# Reset la projection database
cd apps/balados_sync_projections
mix ecto.reset

# Les projectors vont automatiquement replay tous les events
# et reconstruire les projections
```

---

## Checkpoint Pattern

### Problème

Avec Event Sourcing, rebuilder un aggregate nécessite de **replay tous les events** :

```
User avec 10 000 events
→ Rebuild aggregate = replay 10 000 events
⏱️ LENT et coûteux
```

### Solution : Checkpoints

Un checkpoint est un **snapshot de l'état** à un moment donné :

```
Events 1-8000: [événements anciens]
Checkpoint (jour 45): État complet de l'aggregate
Events 8001-10000: [événements récents]

Rebuild aggregate =
  Charger checkpoint + replay events 8001-10000
⏱️ RAPIDE
```

### Per-Aggregate Checkpoint Events

Depuis le split en bounded contexts (#148), les checkpoints sont par aggregate :

```elixir
%SubscriptionCheckpoint{user_id, subscriptions, privacy, timestamp}
%PlayTrackingCheckpoint{user_id, play_statuses, timestamp}
%PlaylistCheckpoint{user_id, playlists, timestamp}
%CollectionCheckpoint{user_id, collections, timestamp}
```

**Legacy** : L'ancien `UserCheckpoint` monolithique est toujours supporté par
les projectors pour la compatibilité avec les events déjà stockés. Les nouveaux
snapshots émettent les 4 variants ci-dessus.

### SnapshotWorker

Runs every **5 minutes** :

```elixir
defmodule BaladosSyncJobs.SnapshotWorker do
  def perform do
    # 1. Trouver events > 45 jours
    old_events = find_old_events(45)

    for user_id <- extract_user_ids(old_events) do
      # 2. Dispatch 4 per-aggregate snapshot commands
      results = [
        Dispatcher.dispatch(%SnapshotSubscription{user_id: user_id}),
        Dispatcher.dispatch(%SnapshotPlayTracking{user_id: user_id}),
        Dispatcher.dispatch(%SnapshotPlaylist{user_id: user_id}),
        Dispatcher.dispatch(%SnapshotCollection{user_id: user_id})
      ]

      # 3. All-or-nothing: only cleanup if ALL snapshots succeed
      if Enum.all?(results, &(&1 == :ok)) do
        cleanup_old_events(user_id, 45)
      end
    end
  end
end
```

### Checkpoint Projection

Le checkpoint est **upsert** dans les projections :

```elixir
project %Checkpoint{} = event, _metadata, fn multi ->
  # Upsert toutes les subscriptions
  Enum.reduce(event.subscriptions, multi, fn {feed, sub}, multi ->
    Ecto.Multi.insert(
      multi,
      {:subscription, feed},
      %Subscription{...},
      on_conflict: :replace_all,
      conflict_target: [:user_id, :rss_source_feed]
    )
  end)

  # Même chose pour play_statuses, playlists, etc.
end
```

---

## Exemples Complets

### Exemple 1 : Subscribe to Podcast

#### Step 1 : Client fait une requête

```bash
POST /api/v1/subscriptions
Authorization: Bearer <jwt_token>
Content-Type: application/json

{
  "feed": "aHR0cHM6Ly9leGFtcGxlLmNvbS9mZWVkLnhtbA=="
}
```

#### Step 2 : Controller crée Command

```elixir
def create(conn, %{"feed" => feed}) do
  user_id = conn.assigns.current_user_id
  device_id = conn.assigns.jwt_claims["device_id"]

  command = %Subscribe{
    user_id: user_id,
    rss_source_feed: feed,
    device_id: device_id,
    device_name: "Web App"
  }

  case Dispatcher.dispatch(command) do
    :ok -> json(conn, %{status: "success"})
    {:error, reason} -> json(conn, %{error: reason})
  end
end
```

#### Step 3 : Aggregate traite Command

```elixir
# Subscription.execute/2
def execute(%Subscription{} = state, %Subscribe{} = cmd) do
  if already_subscribed?(state, cmd.rss_source_feed) do
    {:error, :already_subscribed}
  else
    %UserSubscribed{
      user_id: cmd.user_id,
      rss_source_feed: cmd.rss_source_feed,
      subscribed_at: DateTime.utc_now(),
      device_id: cmd.device_id
    }
  end
end
```

#### Step 4 : Event persisté dans EventStore

```
Stream: user-user_abc123
Event: UserSubscribed
  user_id: "user_abc123"
  rss_source_feed: "aHR0cHM6Ly9leGFtcGxlLmNvbS9mZWVkLnhtbA=="
  subscribed_at: 2025-11-24T10:30:00Z
```

#### Step 5 : Aggregate state updated

```elixir
# Subscription.apply/2
def apply(%Subscription{} = state, %UserSubscribed{} = event) do
  subscription = %{
    feed: event.rss_source_feed,
    subscribed_at: event.subscribed_at
  }

  subscriptions = Map.put(user.subscriptions, event.rss_source_feed, subscription)
  %{user | subscriptions: subscriptions}
end
```

#### Step 6 : Projectors traitent l'Event

**SubscriptionProjector** :
```elixir
# Insert dans site.subscriptions
INSERT INTO site.subscriptions (
  user_id, rss_source_feed, subscribed_at
) VALUES (
  'user_abc123', 'aHR0cHM6Ly9leGFtcGxlLmNvbS9mZWVkLnhtbA==', '2025-11-24 10:30:00'
)
```

**PublicEventsProjector** :
```elixir
# Si privacy = public/anonymous
INSERT INTO site.public_events (
  user_id, event_type, feed, timestamp
) VALUES (
  'user_abc123', 'subscribe', 'aHR0cHM6Ly9leGFtcGxlLmNvbS9mZWVkLnhtbA==', '2025-11-24 10:30:00'
)
```

**PopularityProjector** :
```elixir
# +10 points pour ce podcast
UPDATE site.podcast_popularity
SET score = score + 10
WHERE rss_source_feed = 'aHR0cHM6Ly9leGFtcGxlLmNvbS9mZWVkLnhtbA=='
```

#### Step 7 : Client query

```bash
GET /api/v1/subscriptions
Authorization: Bearer <jwt_token>
```

```elixir
def index(conn, _params) do
  user_id = conn.assigns.current_user_id

  subscriptions = Repo.all(
    from s in Subscription,
    where: s.user_id == ^user_id,
    where: is_nil(s.unsubscribed_at)
  )

  json(conn, %{subscriptions: subscriptions})
end
```

### Exemple 2 : Update Play Position

#### Step 1 : Client request

```bash
PUT /api/v1/plays/abc123/position
Authorization: Bearer <jwt_token>
Content-Type: application/json

{
  "position": 1234
}
```

#### Step 2 : Command

```elixir
command = %UpdatePosition{
  user_id: user_id,
  rss_source_item: "abc123",
  position: 1234,
  played: false,
  device_id: device_id
}

Dispatcher.dispatch(command)
```

#### Step 3 : Aggregate

```elixir
def execute(%PlayTracking{}, %UpdatePosition{} = cmd) do
  %PositionUpdated{
    user_id: cmd.user_id,
    rss_source_item: cmd.rss_source_item,
    position: cmd.position,
    updated_at: DateTime.utc_now()
  }
end

def apply(%PlayTracking{} = state, %PositionUpdated{} = event) do
  play_statuses = state.play_statuses || %{}
  play_status = play_statuses[event.rss_source_item] || %{}
  play_status = Map.merge(play_status, %{
    position: event.position,
    updated_at: event.updated_at
  })

  %{state | play_statuses: Map.put(play_statuses, event.rss_source_item, play_status)}
end
```

#### Step 4 : Projector

```elixir
project %PositionUpdated{} = event, _metadata, fn multi ->
  Ecto.Multi.insert(
    multi,
    :play_status,
    %PlayStatus{
      user_id: event.user_id,
      rss_source_item: event.rss_source_item,
      position: event.position,
      updated_at: event.updated_at
    },
    on_conflict: {:replace, [:position, :updated_at]},
    conflict_target: [:user_id, :rss_source_item]
  )
end
```

---

## Best Practices

### 1. Event Naming

✅ **DO** : Passé, descriptif
```elixir
UserSubscribed
PlayRecorded
PositionUpdated
PlaylistCreated
```

❌ **DON'T** : Présent, vague
```elixir
Subscribe
Play
Update
Create
```

### 2. Event Immutability

✅ **DO** : Nouveaux events pour changements
```elixir
# Change subscription
%UserUnsubscribed{feed: "old"}
%UserSubscribed{feed: "new"}
```

❌ **DON'T** : Modifier events existants
```elixir
# Modifier l'event dans la DB
UPDATE events SET feed = 'new' WHERE id = 123  # ❌
```

### 3. Rich Events

✅ **DO** : Events complets avec toutes les données
```elixir
%UserSubscribed{
  user_id: "user_123",
  rss_source_feed: "...",
  rss_feed_title: "My Podcast",  # Titre capturé
  subscribed_at: ~U[2025-11-24 10:00:00Z],
  device_id: "device_456",
  device_name: "iPhone"  # Contexte
}
```

❌ **DON'T** : Events minimalistes
```elixir
%UserSubscribed{
  user_id: "user_123",
  feed: "..."
  # Manque contexte, difficile à exploiter
}
```

### 4. Idempotent Projectors

✅ **DO** : Upsert avec conflict handling
```elixir
Ecto.Multi.insert(
  multi,
  :subscription,
  subscription,
  on_conflict: {:replace, [:subscribed_at]},
  conflict_target: [:user_id, :rss_source_feed]
)
```

❌ **DON'T** : Insert sans conflict handling
```elixir
Ecto.Multi.insert(multi, :subscription, subscription)
# Si event rejoué → erreur unique constraint
```

### 5. Command Validation

✅ **DO** : Valider dans execute/2
```elixir
def execute(%Subscription{}, %Subscribe{} = cmd) do
  cond do
    String.length(cmd.rss_source_feed) == 0 ->
      {:error, :invalid_feed}

    already_subscribed?(state, cmd.rss_source_feed) ->
      {:error, :already_subscribed}

    true ->
      %UserSubscribed{...}
  end
end
```

❌ **DON'T** : Pas de validation
```elixir
def execute(%Subscription{}, %Subscribe{} = cmd) do
  # Pas de vérification
  %UserSubscribed{...}  # Pourrait créer état invalide
end
```

### 6. Event Versioning

✅ **DO** : Gérer les versions d'events
```elixir
# v1 : Initial
%UserSubscribed{
  user_id: "...",
  feed: "..."
}

# v2 : Ajout champ (compatible)
%UserSubscribed{
  user_id: "...",
  feed: "...",
  feed_title: "..."  # Nouveau champ
}

# Projector gère les deux versions
def project(%UserSubscribed{feed_title: nil} = event, _, multi) do
  # v1 : fetch title séparément
end

def project(%UserSubscribed{feed_title: title} = event, _, multi) do
  # v2 : utilise title directement
end
```

---

## Common Pitfalls

### 1. Querying dans execute/2

❌ **ERREUR** :
```elixir
def execute(%Subscription{}, %Subscribe{} = cmd) do
  # ❌ Query externe dans aggregate
  existing = Repo.get_by(Subscription, feed: cmd.feed)
  if existing, do: {:error, :exists}
end
```

✅ **CORRECT** :
```elixir
def execute(%Subscription{} = state, %Subscribe{} = cmd) do
  # ✅ Utiliser l'état de l'aggregate
  if already_subscribed?(state, cmd.feed) do
    {:error, :already_subscribed}
  end
end
```

### 2. Modifier Event Store Manuellement

❌ **ERREUR** :
```sql
-- ❌ Modifier directement la DB events
UPDATE events.events SET data = '...' WHERE stream_id = 'user-123';
```

✅ **CORRECT** :
```elixir
# ✅ Émettre nouvel event pour corriger
Dispatcher.dispatch(%CorrectiveCommand{...})
```

### 3. Projections Synchrones

❌ **ERREUR** :
```elixir
def create(conn, params) do
  command = %Subscribe{...}
  :ok = Dispatcher.dispatch(command)

  # ❌ Query immédiatement (projection pas encore à jour)
  subscriptions = Repo.all(Subscription)
  json(conn, subscriptions)  # Pourrait manquer la nouvelle sub
end
```

✅ **CORRECT** :
```elixir
def create(conn, params) do
  command = %Subscribe{...}
  :ok = Dispatcher.dispatch(command)

  # ✅ Retourner succès sans query
  json(conn, %{status: "success"})

  # OU attendre projection
  :ok = wait_for_projection()
  subscriptions = Repo.all(Subscription)
end
```

### 4. Events Trop Larges

❌ **ERREUR** :
```elixir
%PlaylistCreated{
  user_id: "...",
  playlist: %{
    id: "...",
    items: [
      %{feed: "...", item: "...", title: "...", ...},  # 1000 items
      # ... tous les items dans l'event
    ]
  }
}
```

✅ **CORRECT** :
```elixir
# Event léger
%PlaylistCreated{
  user_id: "...",
  playlist_id: "...",
  name: "My Playlist"
}

# Events séparés pour items
%PlaylistItemAdded{
  user_id: "...",
  playlist_id: "...",
  item_id: "..."
}
```

### 5. Oublier apply/2

❌ **ERREUR** :
```elixir
# execute/2 défini
def execute(%Subscription{}, %Subscribe{} = cmd) do
  %UserSubscribed{...}
end

# ❌ apply/2 manquant
# L'aggregate state ne sera jamais mis à jour !
```

✅ **CORRECT** :
```elixir
# execute/2
def execute(%Subscription{}, %Subscribe{} = cmd) do
  %UserSubscribed{...}
end

# ✅ apply/2 correspondant
def apply(%Subscription{} = state, %UserSubscribed{} = event) do
  # Mettre à jour state.subscriptions
  %{state | subscriptions: ...}
end
```

---

## Ressources

### Documentation Commanded

- [Commanded Guide](https://hexdocs.pm/commanded/Commanded.html)
- [Event Store](https://hexdocs.pm/eventstore/)
- [Projections](https://hexdocs.pm/commanded/Commanded.Projections.Ecto.html)

### Articles

- [CQRS](https://martinfowler.com/bliki/CQRS.html) - Martin Fowler
- [Event Sourcing](https://martinfowler.com/eaaDev/EventSourcing.html) - Martin Fowler
- [Eventual Consistency](https://www.allthingsdistributed.com/2008/12/eventually_consistent.html) - Werner Vogels

### Livres

- **Domain-Driven Design** - Eric Evans
- **Implementing Domain-Driven Design** - Vaughn Vernon
- **Patterns, Principles, and Practices of Domain-Driven Design** - Scott Millett

### Fichiers Internes

- [ARCHITECTURE.md](ARCHITECTURE.md) : Architecture complète
- [DEVELOPMENT.md](DEVELOPMENT.md) : Commandes de développement
- [AUTH_SYSTEM.md](AUTH_SYSTEM.md) : Système d'autorisation

---

**Dernière mise à jour** : 2025-11-24
