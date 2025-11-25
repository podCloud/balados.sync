# CLAUDE.md - Balados Sync

Ce fichier fournit des instructions à Claude Code (claude.ai/code) pour travailler sur ce repository.

## 📖 Vue d'Ensemble du Projet

**Balados Sync** est une plateforme ouverte de synchronisation de podcasts utilisant **CQRS/Event Sourcing** avec Elixir.

### Objectif Principal

Créer une **plateforme ouverte** pour synchroniser les écoutes de podcasts entre applications et appareils, avec découverte communautaire et support self-hosted.

**👉 Pour en savoir plus** : [docs/GOALS.md](docs/GOALS.md)

### Architecture

Application **Elixir umbrella** avec 4 apps :
- **balados_sync_core** : Domain, CQRS, Event Sourcing (Commanded)
- **balados_sync_projections** : Read Models, Projectors (Ecto)
- **balados_sync_web** : REST API, Controllers (Phoenix)
- **balados_sync_jobs** : Background Workers (Checkpoints, Popularity)

**👉 Architecture détaillée** : [docs/technical/ARCHITECTURE.md](docs/technical/ARCHITECTURE.md)

---

## 🚀 Quick Start

### Installation

```bash
# Dépendances
mix deps.get

# Bases de données
mix ecto.create
mix event_store.create -a balados_sync_core
mix event_store.init -a balados_sync_core

# Migrations
cd apps/balados_sync_projections && mix ecto.migrate && cd ../..
```

### Lancement

```bash
# Serveur dev (http://localhost:4000)
mix phx.server

# Console interactive
iex -S mix
```

**👉 Guide complet** : [docs/technical/DEVELOPMENT.md](docs/technical/DEVELOPMENT.md)

---

## 📚 Documentation Détaillée

### Documentation Technique

| Document | Description |
|----------|-------------|
| [**docs/GOALS.md**](docs/GOALS.md) | Objectifs du projet, vision, roadmap |
| [**docs/technical/ARCHITECTURE.md**](docs/technical/ARCHITECTURE.md) | Architecture complète, structure des apps, flux CQRS/ES |
| [**docs/technical/DEVELOPMENT.md**](docs/technical/DEVELOPMENT.md) | Commandes de dev, tests, debugging, workflow |
| [**docs/technical/AUTH_SYSTEM.md**](docs/technical/AUTH_SYSTEM.md) | Système d'autorisation JWT, scopes, OAuth-style flow |
| [**docs/technical/CQRS_PATTERNS.md**](docs/technical/CQRS_PATTERNS.md) | Patterns CQRS/ES, exemples, best practices |
| [**docs/technical/TESTING_GUIDE.md**](docs/technical/TESTING_GUIDE.md) | Guide de tests du système d'autorisation |

### Documentation API

| Document | Description |
|----------|-------------|
| [**docs/api/authentication.livemd**](docs/api/authentication.livemd) | Guide d'authentification API (JWT, scopes) |

---

## 🎯 Principes Clés

### CQRS/Event Sourcing

- **Commands** : Intentions (Subscribe, RecordPlay, ...)
- **Events** : Faits immuables (UserSubscribed, PlayRecorded, ...)
- **Aggregates** : Logique métier (User aggregate)
- **Projections** : Read models dénormalisés

**Flux** : Command → Aggregate → Event → EventStore → Projectors → Projections

**👉 Patterns détaillés** : [docs/technical/CQRS_PATTERNS.md](docs/technical/CQRS_PATTERNS.md)

### Event Store = Source de Vérité

- ❌ **NE JAMAIS** modifier manuellement la DB `events`
- ✅ Toujours passer par Commanded pour émettre des events
- ✅ Events sont **immuables** (pour "supprimer", émettre nouvel event)

### Projections = Eventual Consistency

- Les projections sont **éventuellement cohérentes** (async)
- Délai normal : quelques millisecondes
- Pour reset : `mix ecto.reset` (safe, replay automatique)

---

## 🔑 Système d'Autorisation

### OAuth-Style JWT Flow

1. **App crée Authorization JWT** (avec public key)
2. **User autorise** via `/authorize?token=...`
3. **AppToken créé** (stocke public_key et scopes)
4. **App fait requêtes API** (JWT signé avec private key)
5. **Server vérifie** avec public_key stockée

### Scopes Hiérarchiques

```
*                         (full access)
├── *.read / *.write
└── user
    ├── user.subscriptions.{read,write}
    ├── user.plays.{read,write}
    ├── user.playlists.{read,write}
    ├── user.privacy.{read,write}
    └── user.sync
```

**Wildcards** : `*`, `*.read`, `user.*`, `user.*.read`

**👉 Documentation complète** : [docs/technical/AUTH_SYSTEM.md](docs/technical/AUTH_SYSTEM.md)

---

## 🧪 Tests

```bash
# Tous les tests
mix test

# Avec couverture
mix test --cover

# App spécifique
cd apps/balados_sync_core && mix test

# Fichier/ligne spécifique
mix test apps/balados_sync_core/test/some_test.exs:42
```

**👉 Guide de développement** : [docs/technical/DEVELOPMENT.md](docs/technical/DEVELOPMENT.md)

---

## 🗄️ Base de Données

### Trois Schémas PostgreSQL

1. **`users`** : Données privées (users, app_tokens, play_tokens)
2. **`site`** : Données publiques (subscriptions, play_statuses, playlists, popularity)
3. **`events`** : EventStore (géré par Commanded, **ne pas modifier manuellement**)

### Migrations

```bash
# Créer migration
cd apps/balados_sync_projections
mix ecto.gen.migration migration_name

# Exécuter migrations
mix ecto.migrate

# Rollback
mix ecto.rollback

# Reset complet (projections uniquement, pas events)
mix ecto.reset
```

---

## 🔧 Commandes IEx Utiles

```elixir
# État d'un aggregate
alias BaladosSyncCore.Dispatcher
Dispatcher.aggregate_state(BaladosSyncCore.Aggregates.User, "user_123")

# Lire event stream
alias BaladosSyncCore.EventStore
EventStore.read_stream_forward("user-user_123")

# Dispatcher une command
alias BaladosSyncCore.Commands.Subscribe
Dispatcher.dispatch(%Subscribe{
  user_id: "user_123",
  rss_source_feed: Base.encode64("https://example.com/feed.xml"),
  device_id: "device_456",
  device_name: "Test Device"
})

# Query projections
alias BaladosSyncProjections.Repo
alias BaladosSyncProjections.Schemas.Subscription
Repo.all(from s in Subscription, where: s.user_id == "user_123")
```

---

## 📊 Workflow d'Ajout de Fonctionnalité

### 1. Créer Command et Event

```elixir
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

### 2. Ajouter Handlers à l'Aggregate

```elixir
# apps/balados_sync_core/lib/balados_sync_core/aggregates/user.ex

# execute/2 : décide de l'event
def execute(%User{} = user, %MyCommand{} = cmd) do
  %MyEvent{
    user_id: cmd.user_id,
    field1: cmd.field1,
    timestamp: DateTime.utc_now()
  }
end

# apply/2 : met à jour l'état
def apply(%User{} = user, %MyEvent{} = event) do
  # Update user state
  %{user | some_field: event.field1}
end
```

### 3. Router la Command

```elixir
# apps/balados_sync_core/lib/balados_sync_core/dispatcher.ex
dispatch [MyCommand], to: BaladosSyncCore.Aggregates.User
```

### 4. Créer Projector (si nécessaire)

```elixir
# apps/balados_sync_projections/lib/projectors/my_projector.ex
defmodule BaladosSyncProjections.Projectors.MyProjector do
  use Commanded.Projections.Ecto,
    application: BaladosSyncCore.Application,
    repo: BaladosSyncProjections.Repo,
    name: "MyProjector"

  project %MyEvent{} = event, _metadata, fn multi ->
    Ecto.Multi.insert(multi, :my_record, %MySchema{...})
  end
end
```

### 5. Ajouter Controller (si endpoint HTTP)

```elixir
# apps/balados_sync_web/lib/controllers/my_controller.ex
defmodule BaladosSyncWeb.MyController do
  use BaladosSyncWeb, :controller

  plug BaladosSyncWeb.Plugs.JWTAuth, [scopes: ["my.scope"]]

  def create(conn, params) do
    command = %MyCommand{user_id: conn.assigns.current_user_id, ...}

    case Dispatcher.dispatch(command) do
      :ok -> json(conn, %{status: "success"})
      {:error, reason} -> json(conn, %{error: reason})
    end
  end
end
```

**👉 Workflow détaillé** : [docs/technical/DEVELOPMENT.md](docs/technical/DEVELOPMENT.md)

---

## ⚠️ Common Gotchas

### Event Store

- ❌ Ne JAMAIS modifier la DB `events` manuellement
- ✅ Events sont immuables (pour "supprimer", émettre nouvel event)
- ✅ Pour reset projections : `mix ecto.reset` (safe)

### Aggregate

- ❌ Pas de queries externes dans `execute/2` (pure function)
- ✅ Utiliser seulement l'état de l'aggregate pour décisions
- ✅ Valider dans `execute/2`, pas dans `apply/2`

### Projections

- ❌ Ne pas assumer synchronisation immédiate (eventual consistency)
- ✅ Utiliser `on_conflict` pour idempotence
- ✅ Projections peuvent être rebuild avec `mix ecto.reset`

### Checkpoints

- ❌ Ne pas appeler `Snapshot` manuellement
- ✅ Laisser `SnapshotWorker` gérer les checkpoints (toutes les 5 min)

---

## 🔐 Configuration d'Environnement

### Variables d'Environnement

```bash
DATABASE_URL="postgresql://user:pass@localhost/balados_sync_dev"
EVENT_STORE_URL="postgresql://user:pass@localhost/balados_sync_eventstore_dev"
SECRET_KEY_BASE="long_secret_key"
PHX_HOST="localhost"
PORT=4000
```

### Subdomain Configuration (Local)

```bash
# /etc/hosts
127.0.0.1 balados.sync play.balados.sync
```

```elixir
# config/dev.exs
config :balados_sync_web, BaladosSyncWeb.Endpoint,
  url: [host: "balados.sync", port: 4000],
  http: [ip: {127, 0, 0, 1}, port: 4000]

config :balados_sync_web,
  play_domain: "play.balados.sync"
```

Accès :
- API principale : `http://balados.sync:4000`
- Play gateway : `http://play.balados.sync:4000`

---

## 🎓 Contexte du Projet

### Niveau d'Expérience

**Intermédiaire** en Elixir et CQRS/ES - j'utilise ces technologies et apprends en pratiquant.

### Défis Techniques

- **Performance du parsing RSS** : Optimisation du fetching concurrent
- **Scalabilité** : Support de milliers d'utilisateurs

### Priorité Actuelle

**Stabilité et fiabilité** du système existant :
- Corriger les bugs identifiés
- Améliorer la robustesse CQRS/ES
- Tests approfondis

**👉 Roadmap complète** : [docs/GOALS.md](docs/GOALS.md)

---

## 📖 Ressources Additionnelles

### Documentation Externe

- [Elixir](https://elixir-lang.org/docs.html)
- [Phoenix](https://hexdocs.pm/phoenix/)
- [Commanded](https://hexdocs.pm/commanded/)
- [EventStore](https://hexdocs.pm/eventstore/)

### Fichiers de Référence

| Fichier | Usage |
|---------|-------|
| `docs/guides/ORIGINAL_NOTE.md` | Instructions initiales de création du projet |
| `.formatter.exs` | Configuration du formatter |

---

## 🤝 Contribution

Le projet vise à devenir open source et communautaire. Guidelines de contribution à venir.

**Vision à long terme** :
- Standard ouvert de sync de podcasts
- Infrastructure self-hostable
- Plateforme de découverte communautaire
- Fédération entre instances

**👉 Vision détaillée** : [docs/GOALS.md](docs/GOALS.md)

---

## 📝 Notes pour Claude Code

### Lors du Travail sur ce Projet

1. **Consulter les docs thématiques** plutôt que de tout garder ici
2. **Respecter les patterns CQRS/ES** : voir [CQRS_PATTERNS.md](docs/technical/CQRS_PATTERNS.md)
3. **Events immuables** : toujours émettre nouveaux events, jamais modifier
4. **Tests** : ajouter tests pour nouveaux commands/events/projectors
5. **Documentation** : mettre à jour docs si changements d'architecture

### Structure de la Documentation

```
/
├── CLAUDE.md                           # Ce fichier (index)
├── README.md                           # Documentation principale
├── docs/
│   ├── GOALS.md                        # Objectifs et vision
│   ├── guides/
│   │   └── ORIGINAL_NOTE.md            # Notes initiales du projet
│   ├── technical/
│   │   ├── ARCHITECTURE.md             # Architecture détaillée
│   │   ├── DEVELOPMENT.md              # Guide de développement
│   │   ├── AUTH_SYSTEM.md              # Système d'autorisation
│   │   ├── CQRS_PATTERNS.md            # Patterns CQRS/ES
│   │   └── TESTING_GUIDE.md            # Guide de tests
│   └── api/
│       └── authentication.livemd       # Documentation API auth
```

---

**Dernière mise à jour** : 2025-11-24
**Statut du projet** : 🟡 En développement actif - Phase de stabilisation
