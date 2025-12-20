# Architecture - Balados Sync

## Vue d'Ensemble

Balados Sync est une **application Elixir umbrella** utilisant **CQRS/Event Sourcing** avec le framework **Commanded** et **EventStore** pour la persistence des événements.

## Structure Umbrella

L'application est organisée en **4 apps principales** :

```
balados.sync/
├── apps/
│   ├── balados_sync_core/        # Domain, CQRS, Event Sourcing
│   ├── balados_sync_projections/ # Read Models, Projectors
│   ├── balados_sync_web/         # REST API, Controllers
│   └── balados_sync_jobs/        # Background Workers
```

---

## 1. balados_sync_core - Domain & CQRS

### Responsabilités
- Définir les **Commands** (intentions utilisateur)
- Définir les **Events** (faits immuables)
- Implémenter les **Aggregates** (logique métier)
- Router les commands via le **Dispatcher**

### Structure
```
apps/balados_sync_core/lib/balados_sync_core/
├── aggregates/
│   └── user.ex                    # Aggregate principal
├── commands/
│   ├── subscribe.ex
│   ├── unsubscribe.ex
│   ├── record_play.ex
│   ├── update_position.ex
│   ├── change_privacy.ex
│   └── ...
├── events/
│   ├── user_subscribed.ex
│   ├── user_unsubscribed.ex
│   ├── play_recorded.ex
│   ├── position_updated.ex
│   ├── privacy_changed.ex
│   └── ...
├── dispatcher.ex                  # Command routing (Commanded)
└── event_store.ex                 # EventStore config
```

### User Aggregate

L'**aggregate User** est le cœur du domaine. Il maintient l'état via Event Sourcing :

#### État de l'Aggregate
```elixir
defstruct [
  user_id: nil,
  subscriptions: %{},      # %{feed_url => subscription_data}
  play_statuses: %{},      # %{item_id => play_status_data}
  playlists: %{},          # %{playlist_id => playlist_data}
  privacy_settings: %{}    # Privacy configuration
]
```

#### Flux de Traitement

1. **Command reçue** (ex: `Subscribe`)
2. **`execute/2`** : Valide et décide quel(s) event(s) émettre
3. **Event persisté** dans EventStore
4. **`apply/2`** : Met à jour l'état de l'aggregate
5. **Projectors** écoutent et mettent à jour les read models

#### Routing

Toutes les commands sont routées vers l'aggregate User via `user_id` :

```elixir
# Dans Dispatcher.Router
identify BaladosSyncCore.Aggregates.User,
  by: :user_id,
  prefix: "user-"
```

---

## 2. balados_sync_projections - Read Models

### Responsabilités
- Définir les **Schemas Ecto** pour les read models
- Implémenter les **Projectors** qui écoutent les events
- Maintenir les données **dénormalisées** pour les queries rapides

### Structure des Données

Trois schémas PostgreSQL distincts :

#### Schema `users`
Tables pour les données utilisateur privées :
- `users` : Comptes utilisateurs
- `app_tokens` : Autorisations d'apps tierces (JWT)
- `play_tokens` : Tokens simples pour play gateway

#### Schema `site`
Tables pour les données publiques/statistiques :
- `subscriptions` : Abonnements de tous les utilisateurs
- `play_statuses` : Statuts d'écoute
- `playlists` : Playlists des utilisateurs
- `playlist_items` : Items dans les playlists
- `public_events` : Événements publics/anonymes (selon privacy)
- `podcast_popularity` : Scores de popularité par podcast
- `episode_popularity` : Scores de popularité par épisode
- `user_privacy` : Configuration de privacy par utilisateur

#### Schema `events`
Géré automatiquement par EventStore (ne pas modifier manuellement).

### Projectors

Les projectors écoutent les events et mettent à jour les read models :

```elixir
# Exemple : SubscriptionProjector
defmodule BaladosSyncProjections.Projectors.SubscriptionProjector do
  use Commanded.Projections.Ecto,
    application: BaladosSyncCore.Application,
    repo: BaladosSyncProjections.Repo,
    name: "SubscriptionProjector"

  project(%UserSubscribed{} = event, _metadata, fn multi ->
    # Insérer/mettre à jour la subscription
    Ecto.Multi.insert(multi, :subscription, %Subscription{
      user_id: event.user_id,
      rss_source_feed: event.rss_source_feed,
      # ...
    })
  end)
end
```

### Projectors Principaux

- **SubscriptionProjector** : Gère subscriptions
- **PlayStatusProjector** : Gère play_statuses
- **PlaylistProjector** : Gère playlists et playlist_items
- **PublicEventsProjector** : Construit site.public_events selon privacy
- **PopularityProjector** : Calcule les scores de popularité
- **UserPrivacyProjector** : Gère user_privacy

---

## 3. balados_sync_web - REST API

### Responsabilités
- Exposer l'**API REST** pour les apps clientes
- Gérer l'**authentification JWT** (RS256)
- Valider les **scopes** et permissions
- Interface web de **gestion d'autorisations**
- **RSS Proxy** et agrégation de feeds

### Structure
```
apps/balados_sync_web/lib/balados_sync_web/
├── controllers/
│   ├── subscription_controller.ex    # GET/POST/DELETE subscriptions
│   ├── play_controller.ex            # GET/POST plays, PUT position
│   ├── privacy_controller.ex         # GET/PUT privacy settings
│   ├── episode_controller.ex         # Saved/liked episodes
│   ├── sync_controller.ex            # POST /sync (bulk sync)
│   ├── public_data_controller.ex     # Public stats, popularity
│   ├── app_auth_controller.ex        # App authorization flow
│   ├── play_gateway_controller.ex    # play.balados.sync redirect
│   └── rss_aggregate_controller.ex   # RSS proxy & aggregation
├── plugs/
│   ├── jwt_auth.ex                   # JWT validation + scope check
│   └── user_auth.ex                  # Session-based auth (web UI)
├── app_auth.ex                       # Authorization logic
├── scopes.ex                         # Scope definitions & matching
└── rss_cache.ex                      # RSS feed caching
```

### Routing Principal

```elixir
# API v1 (JWT authenticated)
scope "/api/v1", BaladosSyncWeb do
  pipe_through [:api, :jwt_auth]

  resources "/subscriptions", SubscriptionController
  resources "/plays", PlayController
  resources "/playlists", PlaylistController
  # ...
end

# Public data (no auth)
scope "/api/v1/public", BaladosSyncWeb do
  pipe_through :api

  get "/podcast/:feed/popularity", PublicDataController, :podcast_popularity
  # ...
end
```

### Subdomain Routing

- **balados.sync** : API principale + interface web
- **play.balados.sync** : Play gateway (tracking + redirect)

---

## 4. balados_sync_jobs - Background Workers

### Responsabilités
- **Snapshot/Checkpoint** : Création de checkpoints périodiques
- **Cleanup** : Nettoyage des anciens events
- **Popularity Calculation** : Recalcul des scores de popularité

### SnapshotWorker

Exécuté toutes les **5 minutes** :

#### Étapes

1. **Trouver les events anciens** (>45 jours)
2. **Créer Checkpoint** avec l'état complet de l'aggregate
3. **Upsert checkpoint** dans les projections
4. **Recalculer popularité** depuis site.public_events
5. **Supprimer events** >45 jours (après checkpoint créé)

#### Scores de Popularité

- **Subscribe** : 10 points
- **Play** : 5 points
- **Save/Like** : 3 points
- **Share** : 2 points

---

## Flux CQRS/Event Sourcing

### Write Side (Commands)

```
Client → HTTP Request (POST /api/v1/subscriptions)
  ↓
Controller (extrait JWT, crée Command)
  ↓
Dispatcher (route vers User aggregate par user_id)
  ↓
Aggregate.execute/2 (validation, retourne Event)
  ↓
EventStore (persiste Event immuable)
  ↓
Aggregate.apply/2 (met à jour état aggregate)
  ↓
Event diffusé aux Projectors
```

### Read Side (Queries)

```
Client → HTTP Request (GET /api/v1/subscriptions)
  ↓
Controller (authentification JWT)
  ↓
Query projections (PostgreSQL via Ecto)
  ↓
Return JSON response
```

### Garanties

- **Write** : Forte cohérence via Event Store
- **Read** : Éventuelle cohérence (projections async)
- **Commands** : Validées par l'aggregate
- **Events** : Immuables, jamais modifiés

---

## Privacy System

### Niveaux de Privacy

| Niveau | Visible dans public_events | User ID inclus |
|--------|----------------------------|----------------|
| `public` | ✅ Oui | ✅ Oui |
| `anonymous` | ✅ Oui | ❌ Non (anonymisé) |
| `private` | ❌ Non | ❌ Non |

### Configuration

- **Global** : Par utilisateur (défaut pour tous)
- **Per-Feed** : Override pour un podcast spécifique
- **Per-Episode** : Override pour un épisode individuel

### Application

Le **PublicEventsProjector** filtre les events selon privacy :
- Lit la config privacy de l'utilisateur
- Vérifie les overrides (feed, episode)
- Insère dans `site.public_events` si public/anonymous
- Anonymise le user_id si anonymous

---

## Data Encoding

### RSS Feeds & Items

Pour éviter les problèmes d'URL encoding dans les routes :

- **`rss_source_feed`** : Feed URL encodée en **base64**
- **`rss_source_item`** : Item ID encodé en **base64**

Format item ID : `"#{guid},#{enclosure_url}"`

Exemple :
```elixir
feed_url = "https://example.com/feed.xml"
feed_encoded = Base.encode64(feed_url)
# => "aHR0cHM6Ly9leGFtcGxlLmNvbS9mZWVkLnhtbA=="

item_id = "episode-123,https://example.com/audio.mp3"
item_encoded = Base.encode64(item_id)
```

### JWT Tokens

Signature **RS256** (asymétrique) :
- Apps tierces signent avec **clé privée**
- API vérifie avec **clé publique** stockée

---

## Checkpoint System

### Pourquoi les Checkpoints ?

- **Performance** : Éviter de rejouer tous les events depuis le début
- **Cleanup** : Pouvoir supprimer les anciens events sans perte de données
- **Récupération** : Point de restauration rapide

### Fonctionnement

1. Event Store contient **tous les events** (initialement)
2. Après 45 jours, **Checkpoint** créé avec état complet
3. Checkpoint **upsert** dans projections (source de vérité)
4. Events >45 jours **supprimés**
5. Rebuild aggregate : charge checkpoint + events récents uniquement

### Structure Checkpoint

```elixir
%Checkpoint{
  user_id: "user_123",
  subscriptions: [...],       # État complet
  play_statuses: [...],
  playlists: [...],
  privacy_settings: {...},
  checkpoint_date: ~U[2025-11-24 12:00:00Z]
}
```

---

## Synchronization Strategy

### Endpoint `/api/v1/sync`

Compare l'état client vs serveur et émet des events pour les différences.

#### Logique de Résolution

**Subscriptions** :
- Compare `subscribed_at` vs `unsubscribed_at`
- Prend le timestamp le plus récent
- Si client plus récent → émet event correspondant

**Play Statuses** :
- Compare `updated_at`
- Prend le plus récent (client ou serveur)

**Playlists** :
- TODO : Nécessite ajout de `added_at` / `removed_at`

#### Post-Sync

Après sync, crée un **checkpoint** pour cet utilisateur.

---

## Scalabilité

### Optimisations Actuelles

- **Projections dénormalisées** : Queries rapides sans joins complexes
- **Event Store** : PostgreSQL optimisé pour append-only
- **RSS Cache** : Cache des feeds RSS pour éviter re-fetching
- **Workers async** : Background jobs non-bloquants
- **Checkpoints** : Évite replay de milliers d'events

### Défis Identifiés

1. **Parsing RSS concurrent** : Optimiser fetching de nombreux feeds
2. **Event Store growth** : Stratégie de sharding à long terme
3. **Projections lag** : Monitoring du délai projections

### Améliorations Futures

- **CQRS Caching** : Cache query results (Redis)
- **Event Store sharding** : Partitionner par user ranges
- **CDN pour RSS** : Distribuer le fetching de feeds
- **Read replicas** : Scaling horizontal des projections

---

## Diagrammes

### Architecture Globale

```
┌─────────────────────────────────────────────────────────────┐
│                         Client Apps                          │
│              (Web, iOS, Android, Desktop)                    │
└───────────────────────────┬─────────────────────────────────┘
                            │ HTTP REST API (JWT RS256)
                            ▼
┌─────────────────────────────────────────────────────────────┐
│                   balados_sync_web                           │
│  ┌──────────────────────────────────────────────────────┐   │
│  │            Controllers + JWT Auth                     │   │
│  └────────────────────────┬─────────────────────────────┘   │
└───────────────────────────┼─────────────────────────────────┘
                            │
            ┌───────────────┴───────────────┐
            │ Commands                      │ Queries
            ▼                               ▼
┌─────────────────────────┐   ┌─────────────────────────────┐
│  balados_sync_core      │   │  balados_sync_projections   │
│  ┌────────────────────┐ │   │  ┌────────────────────────┐ │
│  │ User Aggregate     │ │   │  │  PostgreSQL Schemas    │ │
│  │  - execute/2       │ │   │  │   - users              │ │
│  │  - apply/2         │ │   │  │   - site               │ │
│  └─────────┬──────────┘ │   │  │   - events             │ │
│            │ Events      │   │  └────────────────────────┘ │
│            ▼            │   │            ▲                 │
│  ┌────────────────────┐ │   │            │                 │
│  │   EventStore       │ │───┤   ┌────────┴────────┐       │
│  │   (PostgreSQL)     │ │   │   │   Projectors    │       │
│  └────────────────────┘ │   │   │   (Listeners)   │       │
└─────────────────────────┘   │   └─────────────────┘       │
                              └─────────────────────────────┘
                                          ▲
                                          │
                              ┌───────────┴──────────────┐
                              │  balados_sync_jobs       │
                              │  - SnapshotWorker        │
                              │  - Popularity Calculator │
                              └──────────────────────────┘
```

### CQRS Flow Detail

```
Write Path:
POST /subscriptions → SubscriptionController
  → %Subscribe{} command
    → Dispatcher.dispatch()
      → UserAggregate.execute()
        → %UserSubscribed{} event
          → EventStore.append()
            → UserAggregate.apply()
              │
              └─→ Event Bus
                    │
                    ├─→ SubscriptionProjector → subscriptions table
                    ├─→ PublicEventsProjector → public_events table
                    └─→ PopularityProjector → podcast_popularity table

Read Path:
GET /subscriptions → SubscriptionController
  → Repo.all(Subscription, user_id: ...)
    → PostgreSQL query on projections
      → JSON response
```

---

## System Tables vs Event-Sourced Data

L'application distingue deux types de données selon leur nature :

### Event-Sourced (CQRS)

Données générées par les **actions utilisateur** et nécessitant un **historique complet** :

| Catégorie | Exemples | Source de vérité |
|-----------|----------|------------------|
| Subscriptions | Abonnements, désabonnements | Event Store |
| Play statuses | Progression, écoutes | Event Store |
| Playlists | Création, items, ordre | Event Store |
| Collections | Création, feeds, ordre | Event Store |
| Privacy | Changements de visibilité | Event Store |

**Caractéristiques** :
- Flux : Command → Aggregate → Event → EventStore → Projectors → Projections
- Les projections peuvent être **reconstruites** à partir des events
- L'historique complet est préservé (audit trail automatique)

### System Tables (Direct Ecto)

Données de **configuration** ou **administratives** ne nécessitant pas d'historique :

| Catégorie | Exemples | Schema |
|-----------|----------|--------|
| Comptes | Users, credentials | `system` |
| Auth tokens | App tokens, play tokens | `system` |
| Admin config | Enriched podcasts | `system` |
| User profile | Avatar, bio, public name | `system` |

**Caractéristiques** :
- Gérées directement via Ecto (pas de Command/Event)
- Modifications **écrasent** les valeurs précédentes
- Pour l'audit, ajouter du logging applicatif si nécessaire
- Reset des projections **ne les affecte pas**

### Quand utiliser chaque approche ?

| Critère | Event-Sourced | System Table |
|---------|---------------|--------------|
| Historique requis | ✅ Oui | ❌ Non |
| Actions utilisateur fréquentes | ✅ Oui | ❌ Non |
| Données de configuration | ❌ Non | ✅ Oui |
| Besoin de replay/rebuild | ✅ Oui | ❌ Non |
| Données admin-only | ❌ Non | ✅ Oui |

---

## Technologies

### Core Stack
- **Elixir 1.14+** : Langage principal
- **Phoenix 1.7+** : Framework web
- **Commanded** : CQRS/ES framework
- **EventStore** : Event persistence (PostgreSQL)
- **Ecto** : Database ORM
- **PostgreSQL 14+** : Base de données

### Libraries Importantes
- **Joken** : JWT encoding/decoding (RS256)
- **SweetXml** : XML parsing (RSS feeds)
- **Timex** : Date/time manipulation
- **Req** : HTTP client

### Dev Tools
- **Mix** : Build tool
- **ExUnit** : Testing framework
- **Credo** : Code linting

---

**Voir aussi** :
- [CQRS_PATTERNS.md](CQRS_PATTERNS.md) : Patterns et exemples CQRS/ES
- [AUTH_SYSTEM.md](AUTH_SYSTEM.md) : Système d'autorisation détaillé
- [DEVELOPMENT.md](DEVELOPMENT.md) : Commandes et workflow de développement
