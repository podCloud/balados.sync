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

# Créer BDD et schémas (system + event store)
mix db.create

# Initialiser l'event store
mix event_store.init -a balados_sync_core

# Migrer le schéma system
mix db.init
```

### Lancement

```bash
# Serveur dev (http://localhost:4000)
mix phx.server

# Console interactive
iex -S mix
```

**👉 Guide complet** : [docs/technical/DEVELOPMENT.md](docs/technical/DEVELOPMENT.md)

### Commandes de Base de Données

Pour simplifier la gestion de la BDD, nous avons créé des commandes Mix sécurisées orchestrant deux repos Ecto distincts:

**Installation initiale:**
```bash
# 1️⃣ Créer les BDD (schemas + event store)
mix db.create

# 2️⃣ Initialiser event store + migrer system (combine les deux opérations)
mix db.init
```

#### Architecture Multi-Repo

| Repo | Gère | Migrations | Type |
|------|------|-----------|------|
| **SystemRepo** | Schema `system` | `system_repo/migrations/` | Permanent (CRUD) |
| **ProjectionsRepo** | Schema `public` | `projections_repo/migrations/` | Projections (event-sourcées) |
| **EventStore** | Schema `events` | Commanded | Immuable |

#### Commandes de migration

```bash
# Migrer TOUS les repos (system + projections)
mix db.migrate

# Migrer SEULEMENT SystemRepo (schema system)
mix system.migrate

# Migrer SEULEMENT ProjectionsRepo (schema public)
mix projections.migrate
```

#### Commandes de reset (avec validation)

```bash
# ✅ SAFE - Réinitialiser les projections uniquement
mix db.reset --projections

# ⚠️  DANGER - Réinitialiser system schema (users, tokens)
mix db.reset --system

# ☢️ EXTRÊME DANGER - Réinitialiser event store
mix db.reset --events

# ☢️☢️ EXTRÊME DANGER - Réinitialiser TOUT
mix db.reset --all
```

Chaque reset demande une confirmation explicite.

#### Commandes avancées

```bash
# Créer UNIQUEMENT le schéma system (rarement nécessaire)
mix system_db.create

# Initialiser event store (fait en db.init, rarement seul)
mix event_store.init -a balados_sync_core
```

**⚠️ Important**:
- ❌ **NE PAS UTILISER** `mix ecto.reset`, `ecto.drop`, `ecto.migrate`, `ecto.create` directement
- ✅ Utiliser seulement `mix db.*`, `mix system.migrate`, `mix projections.migrate`
- ❌ Jamais modifier manuellement le schema `events` (géré par Commanded)
- ⚠️ Les resets demandent confirmation pour éviter les accidents

---

## 📚 Documentation Détaillée

### Documentation Technique

| Document | Description |
|----------|-------------|
| [**docs/GOALS.md**](docs/GOALS.md) | Objectifs du projet, vision, roadmap |
| [**docs/technical/ARCHITECTURE.md**](docs/technical/ARCHITECTURE.md) | Architecture complète, structure des apps, flux CQRS/ES |
| [**docs/technical/DATABASE_SCHEMA.md**](docs/technical/DATABASE_SCHEMA.md) | Schémas PostgreSQL, projections vs permanent, commandes reset |
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

**Exception : Deletion Events**
- Les events de type "deletion" (suppression utilisateur) sont une exception à l'immuabilité
- Une fois inscrit dans l'event log, un deletion event supprime tout l'historique concerné
- Seul le deletion event lui-même reste, et disparaîtra après 45 jours

### Projections = Eventual Consistency

- Les projections sont **éventuellement cohérentes** (async)
- Délai normal : quelques millisecondes
- Pour reset : `mix reset_projections` (safe, replay automatique)

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

### Architecture Multi-Repo avec Ecto

Le système utilise **deux Ecto Repositories** distincts pour séparer les responsabilités:

#### **SystemRepo** (Données Permanentes)
- **Gère le schema:** `system`
- **Contient:** users, app_tokens, play_tokens
- **Type:** Données permanentes (JAMAIS event-sourced)
- **Migrations:** `apps/balados_sync_projections/priv/system_repo/migrations/`
- **Commande:** `mix system.migrate`

#### **ProjectionsRepo** (Projections)
- **Gère le schema:** `public` (et optionnellement `users`)
- **Contient:** public_events, podcast_popularity, episode_popularity
- **Type:** Read models event-sourcées (reconstruites depuis events)
- **Migrations:** `apps/balados_sync_projections/priv/projections_repo/migrations/`
- **Commande:** `mix projections.migrate`

#### **EventStore** (Commanded)
- **Gère le schema:** `events`
- **Type:** Source de vérité immuable
- **Gestion:** Automatique via Commanded, ❌ **NE PAS modifier manuellement**

### Configuration Flexible

Ces deux repos peuvent être configurés de plusieurs façons:

**Option 1: Même base PostgreSQL, schemas différents (Par défaut)**
```elixir
# config/dev.exs
config :balados_sync_projections, BaladosSyncProjections.SystemRepo,
  database: "balados_sync_dev",
  hostname: "localhost"

config :balados_sync_projections, BaladosSyncProjections.ProjectionsRepo,
  database: "balados_sync_dev",  # ← Même BDD
  hostname: "localhost"
```

**Option 2: Bases PostgreSQL séparées (Recommandé en production)**
```elixir
# config/prod.exs
config :balados_sync_projections, BaladosSyncProjections.SystemRepo,
  database: "balados_sync_system",   # ← BDD séparée
  hostname: "db-system.example.com"

config :balados_sync_projections, BaladosSyncProjections.ProjectionsRepo,
  database: "balados_sync_projections",  # ← BDD séparée
  hostname: "db-projections.example.com"
```

**Option 3: EventStore sur base séparée**
```elixir
# Configuré dans EVENT_STORE_URL
config :eventstore, EventStore.Config,
  database: "balados_sync_events",  # ← Optionnel: BDD séparée
  hostname: "db-events.example.com"
```

**👉 Détails complets** : [docs/technical/DATABASE_SCHEMA.md](docs/technical/DATABASE_SCHEMA.md)

### Commandes de Migration

```bash
# Migrer TOUS les repos (system + projections)
mix db.migrate

# Migrer SEULEMENT system schema
mix system.migrate

# Migrer SEULEMENT projections
mix projections.migrate

# Créer une migration pour system
cd apps/balados_sync_projections
mix ecto.gen.migration add_column_to_users --prefix system
```

### Reset Commands

```bash
# ✅ SAFE: Reset projections uniquement (préserve users/tokens/events)
mix db.reset --projections

# ⚠️  DANGER: Reset system schema (users, tokens) - demande confirmation
mix db.reset --system

# ☢️  EXTREME DANGER: Reset event store - demande confirmation
mix db.reset --events

# ☢️☢️ EXTREME DANGER: Reset TOUT - demande confirmation
mix db.reset --all
```

**IMPORTANT:** `mix db.reset --all` détruit **TOUTES** les données incluant les events. Utiliser `mix db.reset --projections` pour un reset safe des projections uniquement.

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
- ⚠️ **Exception** : Les deletion events suppriment l'historique concerné (disparaissent après 45j)

### Aggregate

- ❌ Pas de queries externes dans `execute/2` (pure function)
- ✅ Utiliser seulement l'état de l'aggregate pour décisions
- ✅ Valider dans `execute/2`, pas dans `apply/2`

### Projections

- ❌ Ne pas assumer synchronisation immédiate (eventual consistency)
- ✅ Utiliser `on_conflict` pour idempotence
- ✅ Projections peuvent être rebuild avec `mix reset_projections` (SAFE)
- ❌ **ATTENTION:** `mix ecto.reset` détruit TOUT, y compris les events!

### System Data (users, tokens)

- ⚠️  Les données system (users, app_tokens, play_tokens) ne sont **PAS** des projections
- ⚠️  Elles ne peuvent **PAS** être reconstruites depuis les events
- ⚠️  `mix reset_projections` préserve les données system
- ☢️  `mix ecto.reset` détruit les données system ET les events (irréversible!)

### Checkpoints

- `SnapshotWorker` crée automatiquement des checkpoints toutes les 5 min
- Peut être appelé manuellement quand nécessaire (ex: après une suppression)

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

**Dernière mise à jour** : 2025-11-26
**Statut du projet** : 🟡 En développement actif - Phase de stabilisation - Multi-Repo Architecture
- Pour se connecter à postgresql UTILISE LE MDP dans le fichier de config
- always ask me to restart or start phx.server