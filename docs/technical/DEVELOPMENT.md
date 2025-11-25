# Guide de Développement - Balados Sync

Ce guide couvre toutes les commandes et workflows pour développer sur Balados Sync.

## 📦 Installation Initiale

### Prérequis

- **Elixir 1.14+** et **Erlang/OTP 25+**
- **PostgreSQL 14+**
- **Git**

### Setup du Projet

```bash
# Cloner le repository
git clone https://github.com/your-org/balados.sync.git
cd balados.sync

# Installer les dépendances
mix deps.get

# Créer les bases de données
mix ecto.create
mix event_store.create -a balados_sync_core

# Initialiser l'Event Store
mix event_store.init -a balados_sync_core

# Migrer les projections
cd apps/balados_sync_projections
mix ecto.migrate
cd ../..

# Créer un utilisateur (optionnel pour dev)
# Via l'interface web après avoir démarré le serveur
```

---

## 🚀 Lancement de l'Application

### Mode Développement

```bash
# Démarrer le serveur Phoenix (port 4000 par défaut)
mix phx.server

# Serveur accessible à :
# - http://localhost:4000 (API principale)
# - http://balados.sync:4000 (si configuré dans /etc/hosts)
```

### Console Interactive

```bash
# Console IEx avec toutes les apps chargées
iex -S mix

# Exemples de commandes IEx
iex> alias BaladosSyncCore.Dispatcher
iex> alias BaladosSyncCore.Commands.Subscribe
iex> Dispatcher.dispatch(%Subscribe{...})
```

### Mode Production (Local)

```bash
# Build release
MIX_ENV=prod mix release

# Run release
_build/prod/rel/balados_sync/bin/balados_sync start

# Daemon mode
_build/prod/rel/balados_sync/bin/balados_sync daemon

# Stop
_build/prod/rel/balados_sync/bin/balados_sync stop
```

---

## 🧪 Tests

### Exécuter les Tests

```bash
# Tous les tests
mix test

# Tests avec couverture
mix test --cover

# Tests d'une app spécifique
cd apps/balados_sync_core && mix test

# Test d'un fichier spécifique
mix test apps/balados_sync_core/test/aggregates/user_test.exs

# Test d'une ligne spécifique
mix test apps/balados_sync_core/test/aggregates/user_test.exs:42

# Tests en mode watch (reruns automatiques)
mix test.watch
```

### Tests Spécifiques par Tag

```elixir
# Dans un test, ajouter un tag
@tag :integration
test "some integration test" do
  # ...
end
```

```bash
# Exécuter seulement les tests avec ce tag
mix test --only integration

# Exclure certains tags
mix test --exclude slow
```

### Écrire des Tests

#### Test d'un Command/Event

```elixir
defmodule BaladosSyncCore.SubscribeTest do
  use BaladosSyncCore.AggregateCase

  alias BaladosSyncCore.Aggregates.User
  alias BaladosSyncCore.Commands.Subscribe
  alias BaladosSyncCore.Events.UserSubscribed

  describe "Subscribe command" do
    test "emits UserSubscribed event" do
      command = %Subscribe{
        user_id: "user_123",
        rss_source_feed: Base.encode64("https://example.com/feed.xml"),
        device_id: "device_456"
      }

      assert_events(User, command, [
        %UserSubscribed{
          user_id: "user_123",
          rss_source_feed: Base.encode64("https://example.com/feed.xml")
        }
      ])
    end
  end
end
```

#### Test d'un Projector

```elixir
defmodule BaladosSyncProjections.SubscriptionProjectorTest do
  use BaladosSyncProjections.DataCase

  alias BaladosSyncProjections.Schemas.Subscription
  alias BaladosSyncCore.Events.UserSubscribed

  test "projects UserSubscribed event" do
    event = %UserSubscribed{
      user_id: "user_123",
      rss_source_feed: Base.encode64("https://example.com/feed.xml")
    }

    # Dispatch event
    :ok = dispatch_event(event)

    # Verify projection
    subscription = Repo.get_by(Subscription, user_id: "user_123")
    assert subscription != nil
    assert subscription.rss_source_feed == event.rss_source_feed
  end
end
```

---

## 🗄️ Gestion de la Base de Données

### Migrations

```bash
# Créer une nouvelle migration
cd apps/balados_sync_projections
mix ecto.gen.migration add_some_field

# Exécuter les migrations
mix ecto.migrate

# Rollback dernière migration
mix ecto.rollback

# Rollback X migrations
mix ecto.rollback --step 3

# Reset complet (ATTENTION : supprime tout)
mix ecto.reset

# Voir le statut des migrations
mix ecto.migrations
```

### Event Store

```bash
# Créer l'Event Store
mix event_store.create -a balados_sync_core

# Initialiser (créer les tables)
mix event_store.init -a balados_sync_core

# Drop l'Event Store (ATTENTION)
mix event_store.drop -a balados_sync_core
```

### Console PostgreSQL

```bash
# Accéder à la base projections
psql balados_sync_dev

# Accéder à l'Event Store
psql balados_sync_eventstore_dev

# Queries utiles
\dt users.*          # Lister tables du schema users
\dt site.*           # Lister tables du schema site
\d+ users.app_tokens # Décrire une table
```

---

## 🎨 Formatage et Linting

### Formattage du Code

```bash
# Formatter tout le code
mix format

# Formater des fichiers spécifiques
mix format apps/balados_sync_core/lib/balados_sync_core/**/*.ex

# Vérifier sans modifier
mix format --check-formatted
```

### Configuration du Formatter

Fichier `.formatter.exs` à la racine :

```elixir
[
  import_deps: [:ecto, :phoenix, :commanded],
  plugins: [Phoenix.LiveView.HTMLFormatter],
  inputs: [
    "*.{heex,ex,exs}",
    "{config,lib,test}/**/*.{heex,ex,exs}",
    "apps/*/{config,lib,test}/**/*.{heex,ex,exs}"
  ]
]
```

### Linting (Credo)

```bash
# Analyser le code
mix credo

# Analyse stricte
mix credo --strict

# Suggestions uniquement
mix credo suggest

# Formater la sortie
mix credo --format json
```

---

## 🔧 Commandes Utiles IEx

### Aggregate State

```elixir
# Voir l'état complet d'un aggregate
alias BaladosSyncCore.Dispatcher
Dispatcher.aggregate_state(BaladosSyncCore.Aggregates.User, "user_123")
```

### Event Stream

```elixir
# Lire tous les events d'un stream
alias BaladosSyncCore.EventStore
EventStore.read_stream_forward("user-user_123")

# Lire avec limite
EventStore.read_stream_forward("user-user_123", 0, 10)

# Lister tous les streams
EventStore.stream_forward("$all")
```

### Projectors

```elixir
# État d'un projector
BaladosSyncProjections.Projectors.SubscriptionProjector.state()

# Rebuilder un projector (replay tous les events)
# ATTENTION : à utiliser avec précaution
Commanded.Projections.Ecto.rebuild(
  BaladosSyncProjections.Projectors.SubscriptionProjector
)
```

### Dispatch Commands

```elixir
# Dispatcher une command manuellement
alias BaladosSyncCore.Dispatcher
alias BaladosSyncCore.Commands.Subscribe

Dispatcher.dispatch(%Subscribe{
  user_id: "user_123",
  device_id: "device_456",
  device_name: "Test Device",
  rss_source_feed: Base.encode64("https://example.com/feed.xml"),
  rss_source_id: "podcast_123"
})
```

### Queries sur Projections

```elixir
alias BaladosSyncProjections.Repo
alias BaladosSyncProjections.Schemas.{Subscription, PlayStatus, Playlist}

# Toutes les subscriptions d'un user
Repo.all(from s in Subscription, where: s.user_id == "user_123")

# Play statuses récents
Repo.all(
  from p in PlayStatus,
  where: p.user_id == "user_123",
  order_by: [desc: p.updated_at],
  limit: 10
)

# Playlists avec items
Repo.all(from p in Playlist, where: p.user_id == "user_123", preload: :items)
```

---

## 🐛 Debugging

### Logger

```elixir
# Dans le code
require Logger

Logger.debug("Debug message")
Logger.info("Info message")
Logger.warning("Warning message")
Logger.error("Error message")
```

### Configuration du Logger

```elixir
# config/dev.exs
config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

config :logger,
  level: :debug  # ou :info, :warning, :error
```

### IEx.pry

```elixir
# Insérer un breakpoint dans le code
require IEx
IEx.pry()

# Commandes dans pry
# continue : reprendre l'exécution
# respawn : redémarrer le process
```

### Observer

```elixir
# Démarrer Observer (GUI pour monitorer l'application)
:observer.start()
```

### Tracer les Events

```elixir
# config/dev.exs
config :commanded,
  event_store_adapter: Commanded.EventStore.Adapters.EventStore,
  pubsub: :local,
  registry: :local,
  dispatch_consistency_timeout: 5_000,
  log_level: :debug  # Voir tous les events
```

---

## 📦 Dépendances

### Ajouter une Dépendance

```elixir
# Dans mix.exs de l'app concernée
defp deps do
  [
    {:new_dep, "~> 1.0"}
  ]
end
```

```bash
# Installer
mix deps.get

# Mettre à jour
mix deps.update new_dep

# Mettre à jour toutes les deps
mix deps.update --all
```

### Lister les Dépendances

```bash
# Arbre des dépendances
mix deps.tree

# Deps obsolètes
mix hex.outdated

# Deps non utilisées
mix deps.unlock --unused
```

---

## 🔍 Analyse et Profiling

### Dialyzer (Type Checking)

```bash
# Créer PLT (première fois, long)
mix dialyzer --plt

# Analyser le code
mix dialyzer

# Analyser avec format spécifique
mix dialyzer --format dialyxir
```

### Benchmarking

```elixir
# Utiliser Benchee
defmodule MyBench do
  use Benchee

  Benchee.run(%{
    "function_a" => fn -> MyModule.function_a() end,
    "function_b" => fn -> MyModule.function_b() end
  })
end
```

### Profiling

```elixir
# :fprof (natif Erlang)
:fprof.trace([:start])
# ... exécuter du code ...
:fprof.trace([:stop])
:fprof.profile()
:fprof.analyse()

# :eprof (plus simple)
:eprof.start()
:eprof.profile([], &MyModule.my_function/0)
:eprof.analyze()
```

---

## 🌐 Configuration d'Environnement

### Variables d'Environnement

```bash
# .env (ne pas commit)
export DATABASE_URL="postgresql://user:pass@localhost/balados_sync_dev"
export EVENT_STORE_URL="postgresql://user:pass@localhost/balados_sync_eventstore_dev"
export SECRET_KEY_BASE="long_secret_key"
export PHX_HOST="localhost"
export PORT=4000
```

### Fichiers de Configuration

- `config/config.exs` : Configuration commune
- `config/dev.exs` : Configuration développement
- `config/test.exs` : Configuration tests
- `config/prod.exs` : Configuration production
- `config/runtime.exs` : Configuration au démarrage (env vars)

### Subdomain Local Setup

```bash
# Ajouter à /etc/hosts
127.0.0.1 balados.sync play.balados.sync

# config/dev.exs
config :balados_sync_web, BaladosSyncWeb.Endpoint,
  url: [host: "balados.sync", port: 4000],
  http: [ip: {127, 0, 0, 1}, port: 4000]

config :balados_sync_web,
  play_domain: "play.balados.sync"
```

Accès :
- API : `http://balados.sync:4000`
- Play Gateway : `http://play.balados.sync:4000`

---

## 🎯 Workflow de Développement

### Ajout d'une Nouvelle Fonctionnalité

#### 1. Créer Command et Event

```bash
# apps/balados_sync_core/lib/balados_sync_core/commands/my_command.ex
defmodule BaladosSyncCore.Commands.MyCommand do
  defstruct [:user_id, :field1, :field2]
end

# apps/balados_sync_core/lib/balados_sync_core/events/my_event.ex
defmodule BaladosSyncCore.Events.MyEvent do
  @derive Jason.Encoder
  defstruct [:user_id, :field1, :field2, :timestamp]
end
```

#### 2. Ajouter Handlers à l'Aggregate

```elixir
# apps/balados_sync_core/lib/balados_sync_core/aggregates/user.ex

# execute/2 : décide de l'event à émettre
def execute(%User{} = user, %MyCommand{} = cmd) do
  # Validation
  if valid?(cmd) do
    %MyEvent{
      user_id: cmd.user_id,
      field1: cmd.field1,
      field2: cmd.field2,
      timestamp: DateTime.utc_now()
    }
  else
    {:error, :validation_failed}
  end
end

# apply/2 : met à jour l'état
def apply(%User{} = user, %MyEvent{} = event) do
  # Mettre à jour user state
  %{user | some_field: event.field1}
end
```

#### 3. Router la Command

```elixir
# apps/balados_sync_core/lib/balados_sync_core/dispatcher.ex
defmodule BaladosSyncCore.Dispatcher.Router do
  use Commanded.Commands.Router

  identify BaladosSyncCore.Aggregates.User,
    by: :user_id,
    prefix: "user-"

  dispatch [
    # ... autres commands
    BaladosSyncCore.Commands.MyCommand
  ], to: BaladosSyncCore.Aggregates.User
end
```

#### 4. Créer un Projector (si nécessaire)

```elixir
# apps/balados_sync_projections/lib/projectors/my_projector.ex
defmodule BaladosSyncProjections.Projectors.MyProjector do
  use Commanded.Projections.Ecto,
    application: BaladosSyncCore.Application,
    repo: BaladosSyncProjections.Repo,
    name: "MyProjector"

  project %MyEvent{} = event, _metadata, fn multi ->
    # Mettre à jour la projection
    Ecto.Multi.insert(multi, :my_record, %MySchema{
      user_id: event.user_id,
      field1: event.field1
    })
  end
end
```

#### 5. Ajouter un Controller (si endpoint HTTP)

```elixir
# apps/balados_sync_web/lib/controllers/my_controller.ex
defmodule BaladosSyncWeb.MyController do
  use BaladosSyncWeb, :controller

  plug BaladosSyncWeb.Plugs.JWTAuth, [scopes: ["my.scope"]]

  def create(conn, params) do
    user_id = conn.assigns.current_user_id

    command = %MyCommand{
      user_id: user_id,
      field1: params["field1"],
      field2: params["field2"]
    }

    case Dispatcher.dispatch(command) do
      :ok ->
        conn
        |> put_status(:created)
        |> json(%{status: "success"})

      {:error, reason} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: reason})
    end
  end
end
```

#### 6. Tests

```bash
# Tests unitaires aggregate
mix test apps/balados_sync_core/test/aggregates/user_test.exs

# Tests projector
mix test apps/balados_sync_projections/test/projectors/my_projector_test.exs

# Tests controller
mix test apps/balados_sync_web/test/controllers/my_controller_test.exs
```

---

## 🚨 Common Gotchas

### Event Store vs Projections

- ❌ **NE JAMAIS** modifier manuellement la database `events`
- ✅ Toujours passer par Commanded pour émettre des events
- ✅ Pour reset projections : `mix ecto.reset` (safe)
- ❌ Pour reset events : attention, perte de données

### Immutabilité des Events

- Les events sont **immuables**
- Pour "supprimer" : émettre un nouvel event (ex: `SomethingDeleted`)
- Ne jamais changer le schéma d'un event déjà utilisé en production

### Projections Async

- Les projections sont **éventuellement cohérentes**
- Il peut y avoir un léger délai entre command et query
- Pour tests : attendre que les projections soient à jour

### Checkpoints

- Ne pas appeler `Snapshot` manuellement
- Laisse le `SnapshotWorker` gérer les checkpoints
- Si problème : rebuilder les projections

---

## 📚 Ressources

### Documentation Officielle

- [Elixir](https://elixir-lang.org/docs.html)
- [Phoenix](https://hexdocs.pm/phoenix/overview.html)
- [Commanded](https://hexdocs.pm/commanded/)
- [EventStore](https://hexdocs.pm/eventstore/)
- [Ecto](https://hexdocs.pm/ecto/)

### Communauté

- Elixir Forum : https://elixirforum.com/
- Elixir Slack : https://elixir-slackin.herokuapp.com/
- CQRS/ES discussions : Commanded GitHub Issues

### Fichiers Internes

- [ARCHITECTURE.md](ARCHITECTURE.md) : Architecture détaillée
- [CQRS_PATTERNS.md](CQRS_PATTERNS.md) : Patterns CQRS/ES
- [AUTH_SYSTEM.md](AUTH_SYSTEM.md) : Système d'autorisation
- [GOALS.md](../../GOALS.md) : Objectifs du projet
- [TESTING_GUIDE.md](../../TESTING_GUIDE.md) : Guide de tests

---

**Dernière mise à jour** : 2025-11-24
