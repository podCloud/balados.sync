# Balados Sync

Système CQRS/Event Sourcing pour la synchronisation d'écoutes de podcasts, d'abonnements et de playlists.

## Origine

Le système a été codé par Claude.AI en suivant les instructions d'une note présente dans [docs/guides/ORIGINAL_NOTE.md](docs/guides/ORIGINAL_NOTE.md)

## Documentation

- [**CLAUDE.md**](CLAUDE.md) - Guide pour Claude Code (architecture, patterns, workflows)
- [**docs/GOALS.md**](docs/GOALS.md) - Objectifs du projet, vision, roadmap
- [**docs/technical/ARCHITECTURE.md**](docs/technical/ARCHITECTURE.md) - Architecture complète du système
- [**docs/technical/DEVELOPMENT.md**](docs/technical/DEVELOPMENT.md) - Guide de développement
- [**docs/technical/AUTH_SYSTEM.md**](docs/technical/AUTH_SYSTEM.md) - Système d'autorisation JWT
- [**docs/technical/CQRS_PATTERNS.md**](docs/technical/CQRS_PATTERNS.md) - Patterns CQRS/Event Sourcing
- [**docs/technical/TESTING_GUIDE.md**](docs/technical/TESTING_GUIDE.md) - Guide de tests
- [**docs/api/**](docs/api/) - Documentation API (authentication, endpoints)

## Architecture

```
balados_sync/
├── apps/
│   ├── balados_sync_core/        # Domain (CQRS/ES)
│   │   ├── events/                # Events immuables
│   │   ├── commands/              # Intentions
│   │   ├── aggregates/            # Business logic
│   │   └── router.ex              # Command routing
│   ├── balados_sync_projections/  # Read models
│   │   ├── schemas/               # Tables PostgreSQL
│   │   └── projectors/            # Event handlers
│   ├── balados_sync_web/          # API REST
│   │   └── controllers/           # HTTP endpoints
│   └── balados_sync_jobs/         # Workers
│       └── snapshot_worker.ex     # Checkpoints & cleanup
└── config/
```

## Concepts clés

### Event Sourcing
- **Event Store** : Tous les événements sont stockés de façon immuable
- **Checkpoints** : Snapshots créés tous les 5 minutes pour les events > 45 jours
- **Cleanup** : Les events > 45 jours sont supprimés après checkpoint
- ⚠️ **Exception** : Les deletion events suppriment l'historique concerné (disparaissent après 45j)

### Privacy granulaire
- **Public** : Données visibles avec user_id
- **Anonymous** : Données visibles sans user_id
- **Private** : Données cachées

Privacy configurable par :
- Utilisateur (globale)
- Podcast (feed)
- Épisode (item)

### Système de popularité
Scores par action :
- Subscribe : **10 points**
- Play : **5 points**
- Save/Like : **3 points**
- Share : **2 points**

Recalculé toutes les 5 minutes depuis l'event log.

## Installation

### Prérequis
- Elixir 1.17+
- PostgreSQL 14+
- Erlang 26+

### Setup

```bash
# Cloner le projet
git clone <repo>
cd balados_sync

# Installer les dépendances
mix deps.get

# Créer les bases de données (system schema + event store)
mix db.create

# Initialiser l'event store + migrer schéma system
mix db.init

# Lancer le projet
mix phx.server
```

Le serveur démarre sur `http://localhost:4000`

### Commandes de base de données

**Installation initiale:**
```bash
mix db.create     # Crée BDD et event store
mix db.init       # Initialise event store + migre system
```

**Pendant le développement:**
```bash
mix db.migrate        # Migrer le schéma system (après création migration)
mix system_db.migrate # Idem (alias plus verbeux)

# Resets SÉCURISÉS (demandent confirmation):
mix db.reset --projections   # Reset projections uniquement (SAFE) ✅
mix db.reset --system        # Reset system (users, tokens) ⚠️
mix db.reset --events        # Reset event store (EXTREME!) ☢️
mix db.reset --all           # Reset TOUT (EXTREME!) ☢️
```

**Note:** Le projet utilise 4 schémas PostgreSQL distincts :
- **`system`** (permanent) : Users et tokens
- **`events`** (permanent) : Event store (source de vérité)
- **`public`** (transitoire) : Projections publiques (reconstruites depuis events)
- Voir [Architecture de la Base de Données](#architecture-de-la-base-de-données) pour plus de détails

⚠️ **Important:** Les commandes `mix ecto.reset`, `ecto.drop`, `ecto.migrate`, `ecto.create` sont **interdites**. Utilisez `mix db.*` à la place.

## Configuration

### Variables d'environnement

```bash
# Development
export DATABASE_URL="postgresql://postgres:postgres@localhost/balados_sync_dev"
export EVENT_STORE_URL="postgresql://postgres:postgres@localhost/balados_sync_eventstore_dev"
export SECRET_KEY_BASE="your-secret-key"

# Production
export PHX_HOST="api.example.com"
export PORT=4000
```

### Génération de clés JWT (RS256)

```bash
# Générer une paire de clés
openssl genrsa -out private_key.pem 2048
openssl rsa -in private_key.pem -pubout -out public_key.pem
```

### Dépendances supplémentaires

Le projet nécessite les dépendances suivantes (déjà dans mix.exs) :

```elixir
# Core
{:commanded, "~> 1.4"}
{:eventstore, "~> 1.4"}
{:ecto_sql, "~> 3.12"}
{:postgrex, "~> 0.19"}

# Web
{:phoenix, "~> 1.7"}
{:joken, "~> 2.6"}
{:joken_jwks, "~> 1.6"}

# RSS Proxy & Aggregation
{:httpoison, "~> 2.2"}
{:cachex, "~> 3.6"}
{:sweet_xml, "~> 0.7"}
{:timex, "~> 3.7"}

# Jobs
{:quantum, "~> 3.5"}
```

### Configuration du subdomain play

Pour tester en local, ajoutez à `/etc/hosts` :
```
127.0.0.1 balados.sync play.balados.sync
```

Puis dans `config/dev.exs` :
```elixir
config :balados_sync_web, BaladosSyncWeb.Endpoint,
  url: [host: "balados.sync", port: 4000],
  http: [ip: {127, 0, 0, 1}, port: 4000],
  check_origin: false

config :balados_sync_web,
  play_domain: "play.balados.sync"
```

Testez :
```bash
# Devrait répondre normalement
curl http://balados.sync:4000/api/v1/public/trending/podcasts

# Devrait utiliser le PlayGatewayController
curl -L http://play.balados.sync:4000/{token}/{feed}/{item}
```

## Utilisation de l'API

### Authentification

Toutes les requêtes authentifiées nécessitent un JWT dans le header :

```bash
Authorization: Bearer <jwt_token>
```

Le JWT doit contenir :
```json
{
  "sub": "user_id",
  "jti": "unique_token_id",
  "device_id": "device_123",
  "device_name": "iPhone de John",
  "iat": 1234567890,
  "exp": 1234567890
}
```

Signé avec RS256 et la clé privée correspondant à la public key enregistrée.

### Endpoints

#### 1. Synchronisation complète

```bash
POST /api/v1/sync
Content-Type: application/json
Authorization: Bearer <token>

{
  "subscriptions": [
    {
      "rss_source_feed": "aHR0cHM6Ly9leGFtcGxlLmNvbS9mZWVk",
      "rss_source_id": "podcast_id",
      "subscribed_at": "2024-01-15T10:30:00Z",
      "unsubscribed_at": null
    }
  ],
  "play_statuses": [
    {
      "rss_source_feed": "aHR0cHM6Ly9leGFtcGxlLmNvbS9mZWVk",
      "rss_source_item": "ZXBpc29kZV8xMjM=",
      "position": 1250,
      "played": false,
      "updated_at": "2024-01-15T11:00:00Z"
    }
  ],
  "playlists": []
}
```

**Réponse :**
```json
{
  "status": "success",
  "data": {
    "subscriptions": [...],
    "play_statuses": [...],
    "playlists": [...]
  }
}
```

#### 2. Abonnements

```bash
# S'abonner à un podcast
POST /api/v1/subscriptions
{
  "rss_source_feed": "aHR0cHM6Ly9leGFtcGxlLmNvbS9mZWVk",
  "rss_source_id": "podcast_id"
}

# Se désabonner
DELETE /api/v1/subscriptions/aHR0cHM6Ly9leGFtcGxlLmNvbS9mZWVk

# Liste des abonnements actifs
GET /api/v1/subscriptions
```

#### 3. Écoutes

```bash
# Enregistrer une écoute
POST /api/v1/play
{
  "rss_source_feed": "aHR0cHM6Ly9leGFtcGxlLmNvbS9mZWVk",
  "rss_source_item": "ZXBpc29kZV8xMjM=",
  "position": 1250,
  "played": false
}

# Mettre à jour la position
PUT /api/v1/play/ZXBpc29kZV8xMjM=/position
{
  "position": 2500
}

# Liste des statuts de lecture
GET /api/v1/play?played=false&feed=aHR0cHM6Ly9leGFtcGxlLmNvbS9mZWVk&limit=50
```

#### 4. Épisodes

```bash
# Sauvegarder/liker un épisode
POST /api/v1/episodes/ZXBpc29kZV8xMjM=/save?feed=aHR0cHM6Ly9leGFtcGxlLmNvbS9mZWVk

# Partager un épisode
POST /api/v1/episodes/ZXBpc29kZV8xMjM=/share?feed=aHR0cHM6Ly9leGFtcGxlLmNvbS9mZWVk
```

#### 5. Privacy

```bash
# Changer la privacy globale
PUT /api/v1/privacy
{
  "privacy": "anonymous"
}

# Privacy pour un podcast spécifique
PUT /api/v1/privacy
{
  "privacy": "private",
  "feed": "aHR0cHM6Ly9leGFtcGxlLmNvbS9mZWVk"
}

# Privacy pour un épisode spécifique
PUT /api/v1/privacy
{
  "privacy": "public",
  "feed": "aHR0cHM6Ly9leGFtcGxlLmNvbS9mZWVk",
  "item": "ZXBpc29kZV8xMjM="
}

# Voir ses settings de privacy
GET /api/v1/privacy
GET /api/v1/privacy?feed=aHR0cHM6Ly9leGFtcGxlLmNvbS9mZWVk
```

#### 6. Données publiques (pas d'auth)

```bash
# Top podcasts trending
GET /api/v1/public/trending/podcasts?limit=20

# Top épisodes trending
GET /api/v1/public/trending/episodes?limit=20&feed=aHR0cHM6Ly9leGFtcGxlLmNvbS9mZWVk

# Popularité d'un podcast
GET /api/v1/public/feed/aHR0cHM6Ly9leGFtcGxlLmNvbS9mZWVk/popularity

# Popularité d'un épisode
GET /api/v1/public/episode/ZXBpc29kZV8xMjM=/popularity

# Timeline publique
GET /api/v1/public/timeline?limit=50&offset=0&event_type=play&feed=aHR0cHM6Ly9leGFtcGxlLmNvbS9mZWVk
```

#### 7. RSS Proxy avec cache LRU (pas d'auth)

Proxy CORS pour accéder aux flux RSS depuis le navigateur avec cache de 5 minutes :

```bash
# Récupérer un flux RSS complet
GET /api/v1/rss/proxy/aHR0cHM6Ly9leGFtcGxlLmNvbS9mZWVkLnhtbA==
Accept: application/xml

# Filtrer pour un seul épisode (par guid ET enclosure)
GET /api/v1/rss/proxy/aHR0cHM6Ly9leGFtcGxlLmNvbS9mZWVkLnhtbA==/ZXBpc29kZV8xMjMsaHR0cHM6Ly9leGFtcGxlLmNvbS9lcC5tcDM=
Accept: application/xml
```

**Headers de réponse :**
- `Access-Control-Allow-Origin: *`
- `Cache-Control: public, max-age=300`
- `Content-Type: application/xml`

**Cache LRU :**
- 500 entrées max
- TTL de 5 minutes
- Eviction automatique LRU (Least Recently Used)

#### 8. RSS Agrégé par utilisateur (avec user_token)

Flux RSS personnalisés construits dynamiquement :

```bash
# Tous les épisodes de mes abonnements (100 derniers)
GET /api/v1/rss/user/{user_token}/subscriptions
Accept: application/xml

# Épisodes d'une playlist
GET /api/v1/rss/user/{user_token}/playlist/{playlist_id}
Accept: application/xml
```

**Fonctionnalités :**
- Fetch parallèle de tous les feeds via le proxy RSS
- Merge des épisodes triés par date (desc)
- Préfixe du nom du podcast : `[Tech Talks] Episode 42`
- URLs enclosure remplacées par les passerelles play
- Cache privé de 1 minute

**Génération d'un user_token :**
```bash
POST /api/v1/tokens
Authorization: Bearer <jwt>
{
  "name": "My RSS Reader"
}

# Réponse:
{
  "token": "randomBase64Token",
  "user_id": "user_123"
}
```

#### 9. Play Gateway (subdomain play.balados.sync)

Passerelle qui enregistre une écoute et redirige vers l'enclosure :

```bash
# Format: https://play.balados.sync/{user_token}/{feed_id}/{item_id}
GET https://play.balados.sync/randomToken123/aHR0cHM6Ly9leGFtcGxlLmNvbS9mZWVk/ZXBpc29kZV8xMjMsaHR0cHM6Ly9leGFtcGxlLmNvbS9lcC5tcDM=
```

**Workflow :**
1. Vérifie le `user_token`
2. Decode `feed_id` et `item_id` (base64)
3. Dispatch une commande `RecordPlay` (async)
4. Redirige 302 vers l'URL de l'enclosure réelle

**Usage dans les flux agrégés :**
Tous les flux RSS personnalisés (`/user/:token/subscriptions` et `/playlist/:id`) utilisent automatiquement ces URLs comme enclosures, permettant de tracker les écoutes.

**Exemple de réponse trending :**
```json
{
  "podcasts": [
    {
      "rss_source_feed": "aHR0cHM6Ly9leGFtcGxlLmNvbS9mZWVk",
      "feed_title": "Tech Talks",
      "feed_author": "John Doe",
      "feed_cover": {
        "src": "https://example.com/cover.jpg",
        "srcset": "..."
      },
      "score": 25420,
      "score_previous": 20000,
      "plays": 3420,
      "plays_previous": 3000,
      "plays_people": ["user1", "user2", "user3"],
      "likes": 340,
      "likes_previous": 300
    }
  ]
}
```

## Architecture de la Base de Données

La base de données PostgreSQL utilise **4 schémas distincts** gérés par **2 Ecto Repositories** :

### Architecture Multi-Repo

#### SystemRepo (Données Permanentes)
**Gestion**: `mix system.migrate`

Contient les données permanentes via la gestion de Ecto (CRUD direct) :
- `users` : Utilisateurs enregistrés
- `app_tokens` : Tokens JWT valides (App Auth)
- `play_tokens` : Tokens de partage RSS

**Caractéristiques**:
- ❌ NOT event-sourced (JAMAIS)
- ✅ Direct CRUD operations via Ecto
- ⚠️  Données permanentes (non reconstruisibles)

#### ProjectionsRepo (Projections Publiques)
**Gestion**: `mix projections.migrate`

Contient les **projections reconstruites** depuis les events (read models) :
- **Schéma `public`** : Données publiques
  - `public_events` : Events publics/anonymes filtrés
  - `podcast_popularity` : Stats de popularité par podcast
  - `episode_popularity` : Stats de popularité par épisode
  - `subscriptions` : Abonnements utilisateurs

**Caractéristiques**:
- ✅ Event-sourced (reconstruites depuis EventStore)
- ✅ Peuvent être réinitialisées sans crainte (`mix db.reset --projections`)
- 🔄 Automatiquement reconstruites via les projectors

#### EventStore (Commanded)
**Gestion**: `mix event_store.init -a balados_sync_core` (une seule fois)

Contient **tous les événements immuables** du système :
- Chaque action (Subscribe, Play, etc.) crée un event
- Les events sont immuables (pour "supprimer", émettre nouvel event)
- Exception: Les deletion events suppriment l'historique concerné

**Important**: ❌ **NE JAMAIS** modifier manuellement. Géré uniquement par Commanded.

### Configuration Flexible

Ces deux repos **peuvent être dans la même BDD PostgreSQL avec schemas différents** (par défaut en dev) :
```sql
-- Une seule BDD avec 3 schemas
CREATE SCHEMA system;    -- SystemRepo
CREATE SCHEMA public;    -- ProjectionsRepo
CREATE SCHEMA events;    -- EventStore
```

Ou **séparés en différentes BDD** pour une meilleure isolation (recommandé en prod) :
```
balados_sync_system      → SystemRepo (schema system)
balados_sync_projections → ProjectionsRepo (schema public)
balados_sync_events      → EventStore (schema events)
```

### Commandes Référence

| Commande | Cible | Contenu |
|----------|-------|---------|
| `mix db.create` | Tous | Crée BDD et schemas |
| `mix db.init` | system + events | Initialise tout d'un coup |
| `mix db.migrate` | system + projections | Migre les deux repos |
| `mix system.migrate` | system | Migre SEULEMENT SystemRepo |
| `mix projections.migrate` | public | Migre SEULEMENT ProjectionsRepo |

### Reset Commands

```bash
# ✅ SAFE - Reset projections uniquement (preserve system + events)
mix db.reset --projections

# ⚠️  DANGER - Reset system schema (users, tokens)
mix db.reset --system

# ☢️ EXTREME - Reset event store
mix db.reset --events

# ☢️☢️ EXTREME - Reset TOUT
mix db.reset --all
```

**Danger**:
- ❌ `mix ecto.reset` = Réinitialise TOUT (events + system), **éviter**
- ✅ `mix db.reset --projections` = Réinitialise projections seulement, **SAFE**

## Worker de maintenance

Le `SnapshotWorker` s'exécute **toutes les 5 minutes** :

1. **Checkpoint** : Crée des snapshots pour les users avec events > 45 jours
2. **Recalcul** : Met à jour la popularité avec le système de points
3. **Cleanup** : Supprime les events > 45 jours (après checkpoint)

Configuration dans `config/config.exs` :
```elixir
config :balados_sync_jobs, BaladosSyncJobs.Scheduler,
  jobs: [
    {"*/5 * * * *", {BaladosSyncJobs.SnapshotWorker, :perform, []}}
  ]
```

## Développement

### Tests

```bash
# Lancer tous les tests
mix test

# Tests d'une app spécifique
cd apps/balados_sync_core
mix test

# Avec coverage
mix test --cover
```

### Console interactive

```bash
# Console avec toutes les apps chargées
iex -S mix

# Dispatcher une command
alias BaladosSyncCore.App
alias BaladosSyncCore.Commands.Subscribe

App.dispatch(%Subscribe{
  user_id: "user_123",
  device_id: "device_456",
  device_name: "iPhone",
  rss_source_feed: "base64_feed",
  rss_source_id: "podcast_id"
})

# Query les projections
alias BaladosSyncProjections.Repo
alias BaladosSyncProjections.Schemas.Subscription
Repo.all(Subscription)
```

### Replay d'events

Si vous devez reconstruire les projections :

```bash
# Arrêter les projectors
# Supprimer les données des projections (pas l'event store !)
mix ecto.reset

# Les projectors vont automatiquement rejouer tous les events
```

## Encodage RSS

Les `rss_source_feed` et `rss_source_item` utilisent base64 :

```elixir
# Feed
feed_url = "https://example.com/feed.xml"
rss_source_feed = Base.encode64(feed_url)

# Item (guid + enclosure)
guid = "episode-123"
enclosure = "https://example.com/episode.mp3"
rss_source_item = Base.encode64("#{guid},#{enclosure}")
```

## Production

### Déploiement

```bash
# Build release
MIX_ENV=prod mix release

# Lancer
_build/prod/rel/balados_sync/bin/balados_sync start
```

### Monitoring

Le système expose des métriques via Phoenix LiveDashboard :

```
http://localhost:4000/dashboard
```

Métriques importantes :
- Nombre d'events dans l'event store
- Latence des projections
- Nombre de users actifs
- Popularité en temps réel

## Troubleshooting

### Les projections sont en retard

```bash
# Vérifier l'état des projections
iex -S mix
BaladosSyncProjections.Projectors.SubscriptionProjector.state()
```

### Événements manquants

Les events sont immuables. Si des données semblent manquer, vérifiez :
1. Les filtres de privacy
2. Les checkpoints récents
3. Les logs du worker

### Performance

Pour améliorer les performances :
1. Rafraîchir les vues matérialisées : `REFRESH MATERIALIZED VIEW site.trending_podcasts`
2. Analyser les index : `ANALYZE users.subscriptions`
3. Augmenter le pool size PostgreSQL dans la config

## Licence

MIT

## Support

Pour toute question : support@balados-sync.example.com
