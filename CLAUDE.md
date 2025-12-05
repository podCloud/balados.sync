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

## 🎙️ Fonctionnalités Récentes

### Web Subscription Interface (v1.0)

**Nouvelle fonctionnalité** : Interface web complète pour la gestion des abonnements RSS des utilisateurs.

#### Contenu

- **Gestion des Abonnements** : Ajouter, visualiser, supprimer des abonnements
  - Page `/my-subscriptions` : Liste tous les abonnements avec couvertures et descriptions
  - Page `/my-subscriptions/new` : Formulaire d'ajout avec prévisualisation du flux
  - Page `/my-subscriptions/:feed` : Détails du flux et liste des épisodes récents
  - Bouton `/my-subscriptions/export.opml` : Export OPML de tous les abonnements

- **Métadonnées Asynchrones** : Chargement intelligent des métadonnées RSS
  - Métadonnées stockées au moment de l'abonnement (title, author, description, cover, episodes_count, language)
  - Enrichissement asynchrone dans le projector (ne bloque pas l'événement)
  - Rafraîchissement AJAX sur la page d'abonnements pour charger les métadonnées manquantes
  - Endpoint API : `GET /api/v1/subscriptions/:feed/metadata` (authentifié)

- **Découverte Publique** : Pages de tendances accessibles à tous
  - `/trending/podcasts` : Top 10 des podcasts par popularité
  - `/trending/episodes` : Top 10 des épisodes par popularité
  - `/podcasts/:feed` : Page publique d'un podcast avec épisodes récents
  - `/episodes/:item` : Page publique d'un épisode avec statistiques

#### Architecture

**Composants Principaux** :
- `RssParser` : Module de parsing RSS utilisant SweetXml pour extraire métadonnées et épisodes
- `RssCache` : Mise en cache à deux niveaux (XML brut + métadonnées parsées) avec TTL de 5 min
- `WebSubscriptionsController` : 6 actions pour CRUD + export OPML
- `SubscriptionsProjector` : Enrichissement asynchrone des métadonnées via Task.start
- `PublicController` : 4 actions pour pages de découverte publiques
- `subscriptions.js` : Progressive enhancement pour chargement AJAX des métadonnées

**Patterns CQRS** :
- Subscribe/Unsubscribe commands dispatched via Dispatcher
- Projections avec eventual consistency pour métadonnées
- Device ID généré depuis IP hash (pour interface web)

**Codage des URLs** :
- Feeds : Base64 URL-encoded sans padding
- Episodes : Format base64("feed_url,guid,enclosure_url") pour identification unique

#### Utilisation

**Pour les Utilisateurs Authentifiés** :
```
GET  /my-subscriptions           # Lister abonnements
GET  /my-subscriptions/new       # Formulaire d'ajout
POST /my-subscriptions           # Créer abonnement
GET  /my-subscriptions/:feed     # Voir détails flux
DELETE /my-subscriptions/:feed   # Supprimer abonnement
GET  /my-subscriptions/export.opml # Télécharger OPML
```

**Pour Tous** (Public) :
```
GET /trending/podcasts           # Top 10 podcasts
GET /trending/episodes           # Top 10 épisodes
GET /podcasts/:feed              # Détails podcast
GET /episodes/:item              # Détails épisode
```

**API Interne** (Authentifiée) :
```
GET /api/v1/subscriptions/:feed/metadata  # Récupérer métadonnées
```

#### Commits

9 commits implémentant la feature complète :
- RSS Parser module et intégration cache
- Enrichissement asynchrone des métadonnées
- Endpoint API pour métadonnées
- Controller web avec actions CRUD + OPML
- Templates pour gestion des abonnements
- Routes et navigation
- Pages de découverte publiques
- JavaScript AJAX pour chargement asynchrone

### Play Gateway Links with Automatic "Balados Web" Token (v1.1+)

**Nouvelle fonctionnalité** : Les liens d'épisodes de l'interface web utilisent automatiquement la play gateway pour tracker les écoutes, avec support flexible domain/path.

#### Contenu

- **Tokens de Lecture Automatiques** : Token "Balados Web" créé automatiquement
  - Créé lors de la première consultation d'une subscription
  - Stocké dans `system.play_tokens` (données permanentes)
  - Génération sécurisée avec 32 bytes aléatoires (Base64url)

- **Modes Play Gateway Simples** : Support de deux modes pour développement/production
  - **External domain mode** (production) : `https://{play_domain}/{token}/{feed}/{item}`
    - Activation : ajouter `config :balados_sync_web, play_domain: "play.example.com"` en production
  - **Local path mode** (développement, défaut) : `/play/{token}/{feed}/{item}`
    - Automatique si `play_domain` n'est pas configuré (meilleur pour single-domain dev)

- **Links de Play Gateway dans l'Interface Web** : Épisodes et feeds agrégés utilisent la play gateway
  - Template `/my-subscriptions/:feed` utilise le play gateway pour les liens d'enclosure
  - RSS agrégé (subscriptions + playlists) transforme les enclosures pour tracking
  - Permet le tracking automatique des écoutes via RecordPlay command

#### Architecture

**Composants Principaux** :
- `PlayTokenHelper` : Module helper pour get_or_create du token et construction d'URLs
  - `get_or_create_balados_web_token/1` : Crée le token si absent, le retourne sinon
  - `get_balados_web_token/1` : Récupère le token existant si valide
  - `create_balados_web_token/1` : Crée un nouveau token (gère les races conditions)
  - `build_play_url/3` : Construit l'URL selon la configuration (`play_domain` ou `/play/`)
- `WebSubscriptionsController.show/2` : Crée automatiquement le token au premier accès
- `RssAggregateController` : Utilise `build_play_url` pour transformer les feeds
- `show.html.heex` : Génère les URLs play gateway avec le token
- Routes : Support du path mode `/play/:token/:feed/:item` (et subdomain si play_domain externe)

**Patterns Utilisés** :
- Automatic creation on first use (lazy initialization)
- PlayToken stored in `system` schema (permanent data, non-event-sourced)
- Race condition handling via unique constraint on (user_id, name)
- Simple URL generation : `build_play_url` retourne soit une URL externe soit un path relatif

#### Configuration

**Production (external domain)** :
```elixir
config :balados_sync_web,
  play_domain: "play.example.com"  # URLs: https://play.example.com/...
```

**Développement (local path, défaut)** :
```elixir
# Aucune configuration nécessaire
# URLs: /play/token/feed/item (routes locales)
```

#### Utilisation

**Automatique** : Aucune action utilisateur requise
- Premier accès à `/my-subscriptions/:feed` crée un token "Balados Web"
- Token utilisé automatiquement pour tous les liens d'enclosure
- Token partagé pour tous les feeds de l'utilisateur
- Mode (external/path) choisi automatiquement selon configuration

**Données Techniques** :
- Token : 32 bytes random → Base64url (43 caractères)
- Stockage : Table `system.play_tokens` (colonne `name = 'Balados Web'`)
- Lifecycle : Créé une fois, réutilisé, peut être révoqué via `revoked_at`
- Encodage : Tous les feed_id et item_id utilisent `Base.url_encode64(..., padding: false)` pour la sécurité des URLs

#### Commits

3 commits implémentant la feature complète :
- Création du module PlayTokenHelper avec logique de création/retrieval et build_play_url simple
- Ajout du support path mode + mise à jour controllers, templates et routes
- Fix: utilisation de Base.url_encode64/url_decode64 pour tous les IDs dans les URLs

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

### Prérequis pour chaque session
- Pour se connecter à postgresql UTILISE LE MDP dans le fichier de config
- Tu ne peux pas démarrer ou arrêter le server phoenix. Demande moi de le faire et attends ma confirmation
- Mets à jour Claude.md ou les fichiers de docs correspondants à chaque commit

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

### Gestion des Bugs Connus

Tous les bugs connus ont été résolus. Fichier `docs/KNOWN_BUGS.md` supprimé.

---

## 🔧 Live WebSocket Gateway (v1.2)

**Nouvelle fonctionnalité** : WebSocket standard pour communication temps réel avec authentification PlayToken/JWT.

### Contenu

- **WebSocket Standard** (pas Phoenix Channels)
  - Compatible avec JS vanilla et n'importe quelle app tierce
  - Implémente WebSock behaviour (standard Elixir)
  - Pas de dépendance à une librairie client Phoenix spécifique

- **Authentification Duale**
  - **PlayToken** : Simple bearer token (B64url, 32 bytes)
  - **JWT AppToken** : Full JWT avec scopes
  - Détection automatique du type de token
  - Premier message DOIT être `{"type": "auth", "token": "xxx"}`

- **State Management**
  - Connexion commencée en `:unauthenticated`
  - Transition à `:authenticated` après validation
  - Seul `{"type": "auth"}` accepté avant auth
  - État persistent pendant la connexion

- **Message Format** (JSON)
  ```json
  {"type": "auth", "token": "xxx"}
  {"type": "record_play", "feed": "...", "item": "...", "position": 123, "played": false}
  ```

- **Réponses**
  ```json
  {"status": "ok", "message": "...", "data": {...}}
  {"status": "error", "error": {"message": "...", "code": "..."}}
  ```

### Architecture

**Modules Créés** :
- `LiveWebSocket.State` : Gestion d'état de connexion
- `LiveWebSocket.Auth` : Authentification PlayToken/JWT
- `LiveWebSocket.MessageHandler` : Parsing, validation, dispatch
- `LiveWebSocket` : Handler WebSocket (WebSock behaviour)
- `LiveWebSocketController` : HTTP upgrade

**Routes** :
- **Production (subdomain)** : `GET /api/v1/live` (host: "sync.")
- **Production (path)** : `GET /sync/api/v1/live`
- **Développement** : `ws://localhost:4000/sync/api/v1/live`

**Intégration** :
- Réutilise `AppAuth.verify_app_request/1` pour JWT
- Réutilise `PlayToken` schema et validation
- Dispatch synchrone via `Dispatcher.dispatch(RecordPlay)`
- Updates `last_used_at` async (Task.start)

### Utilisation

**Client JavaScript** :
```javascript
const ws = new WebSocket('ws://localhost:4000/sync/api/v1/live');

ws.onopen = () => {
  ws.send(JSON.stringify({type: 'auth', token: 'your_token'}));
};

ws.onmessage = (e) => {
  const response = JSON.parse(e.data);
  if (response.status === 'ok' && response.data?.user_id) {
    // Authentifié
    ws.send(JSON.stringify({
      type: 'record_play',
      feed: btoa(feedUrl).replace(/\+/g, '-').replace(/\//g, '_').replace(/=/g, ''),
      item: btoa(itemId).replace(/\+/g, '-').replace(/\//g, '_').replace(/=/g, ''),
      position: 123,
      played: false
    }));
  }
};
```

### Commits

1 commit implémentant la feature complète :
- Modules WebSocket avec authentification duale
- Routes avec support subdomain + path
- Intégration avec CQRS/Event Sourcing existant

---

## 🔧 Corrections & Améliorations Récentes (2025-12-05)

### Fixes de Configuration et Démarrage
- **Fix TypeScript watcher cassé** : Supprimé le watcher TypeScript invalide qui utilisait `FS.cmd` (module non disponible) causant 5000+ erreurs par requête HTTP
- **Ajout Hammer config** : Configuration manquante pour le rate limiting du WebSocket (expiry_ms + cleanup_interval_ms)
- **Fix dev.exs** : Correction de la syntaxe du watcher TypeScript initial qui causait une compilation impossible

### WebSocket JavaScript - Debugging et Logging
- **Logging complet** du cycle de vie dispatch_events.ts :
  - Log au chargement du module
  - Log lors de la lecture des meta tags
  - Log de l'état du DOM (loading vs déjà loaded)
  - Log de l'endpoint et token configurés
  - Log de completion de l'initialisation
- **Gestion de DOMContentLoaded** : Support des deux cas (script defer qui arrive trop tard vs script qui s'exécute au bon moment)
- **Debugging facilité** : `window.__dispatchEventsManager` disponible pour debugging console

### Résultat
- ✅ WebSocket fonctionne correctement
- ✅ dispatch_events.ts compilé et chargé (~5000 lignes dans app.js)
- ✅ Logging visible dans la console pour déboguer les problèmes de connexion
- ✅ Serveur démarre sans erreur

---

## 🔧 Améliorations Antérieures (2025-12-03)

### Refactoring RSS Cache et Parser
- **Déplacement vers Core** : `RssCache` et `RssParser` ont été déplacés de `balados_sync_web` vers `balados_sync_core` pour éviter dépendances circulaires
- **Dépendances ajoutées à Core** : `httpoison`, `cachex`, `sweet_xml`
- **Web devient client** : `balados_sync_web` appelle `BaladosSyncCore.RssCache` et `BaladosSyncCore.RssParser` directement

### Enrichissement Async Métadonnées
- **PopularityProjector enrichit async** : Lors d'un PlayRecorded, enrichit `episode_popularity` avec titre/auteur/description/cover depuis RSS
- **Podcast title** : Nouveau champ `podcast_title` ajouté à `EpisodePopularity` (migration appliquée)
- **Source de vérité** : Les données RSS sont toujours à jour (synchronisation à chaque play)

### Logging Amélioré
- **Logs détaillés** partout dans PopularityProjector pour debugguer les problèmes
- **Exception handling** : try/rescue blocks avec messages d'erreur explicites
- **Trace complète** : PlayRecorded event → podcast update → episode update → async enrichment

---

### Liens Externes - target=_blank (Fire and Forget WebSocket)
- **Problème identifié**: Les liens avec `data-dispatch-event="play"` utilisaient `preventDefault()` + `window.location.href`, ignorant `target="_blank"`
- **Fix appliqué**: Changement en approche fire-and-forget
  - N'annule plus l'événement default
  - Envoie l'événement WebSocket en arrière-plan
  - Laisse le navigateur gérer le lien normalement
  - Les erreurs WebSocket n'affectent pas l'ouverture du lien
- **Résultat**: Les enclosures s'ouvrent dans un nouvel onglet et l'event est enregistré en background

**Dernière mise à jour** : 2025-12-05
**Statut du projet** : 🟢 Stable - WebSocket fonctionnel, Tous les problèmes résolus
**Branche en cours** : main
**Statuts des Tâches** :
1. ✅ WebSocket fonctionnel avec logging complet
2. ✅ Configuration Hammer pour rate limiting
3. ✅ Tous les watchers fonctionnent sans erreur
4. ✅ Liens externes ouvrent dans nouvel onglet (fire-and-forget WebSocket)
- tu peux lancer mix phx.server mais pas arrêter un existant avec pkill ou autre, il faut me demander si c'est pas un de tes shell qui controle le server