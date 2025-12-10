# Fonctionnalités - Vue Exhaustive

Documentation complète de toutes les fonctionnalités implémentées, organisées par domaine.

---

## 🔐 Authentification & Autorisation

### Système d'Authentification (Core)

**JWT OAuth-style** avec public/private key cryptography :

1. **App crée Authorization JWT** (avec public key)
2. **User autorise** via `/authorize?token=...`
3. **AppToken créé** (stocke public_key et scopes)
4. **App fait requêtes API** (JWT signé avec private key)
5. **Server vérifie** avec public_key stockée

**Scopes Hiérarchiques** :
```
*                              (full access)
├── *.read / *.write
└── user
    ├── user.subscriptions.{read,write}
    ├── user.plays.{read,write}
    ├── user.playlists.{read,write}
    ├── user.privacy.{read,write}
    └── user.sync
```

**Routes** :
- `POST /auth/authorize` - Authorize app
- `POST /auth/tokens` - Create AppToken
- API endpoints avec `Authorization: Bearer <jwt>`

**Modules** :
- `AppAuth` - Verification
- `JWTAuth` plug - Controller protection

**Documentation** : [docs/technical/AUTH_SYSTEM.md](docs/technical/AUTH_SYSTEM.md)

---

## 🎙️ Gestion des Abonnements

### Web Subscription Interface (v1.0)

Interface web complète pour gérer les abonnements podcasts.

**Pages** :
- `GET /subscriptions` - Liste des abonnements authentifiés
- `GET /subscriptions/new` - Formulaire d'ajout
- `POST /subscriptions` - Créer abonnement
- `GET /subscriptions/export.opml` - Télécharger OPML

**Métadonnées Asynchrones** :
- Extraction titre, auteur, description, couverture, language
- Parsing RSS avec SweetXml
- Cache 2 niveaux : XML brut (5 min) + métadonnées parsées (5 min)
- Enrichissement async via `Task.start` (ne bloque pas event)

**API Interne** :
- `GET /api/v1/subscriptions/:feed/metadata` - Récupérer métadonnées

**Modules** :
- `RssParser` - Parsing RSS
- `RssCache` - Cache avec TTL
- `WebSubscriptionsController` - CRUD
- `SubscriptionsProjector` - Enrichissement async

**CQRS** :
- `Subscribe` command - Créer abonnement
- `Unsubscribe` command - Supprimer abonnement
- `UserSubscribed` event
- `UserUnsubscribed` event
- Device ID généré depuis IP hash

**Encodage URLs** :
- Feeds : Base64 URL-encoded sans padding
- Episodes : Base64("feed_url,guid,enclosure_url")

### Collections & Organization (v1.8)

Système CQRS/Event Sourcing pour organiser les abonnements en collections.

**Commandes CQRS** :
- `CreateCollection` - Créer une collection avec titre
- `DeleteCollection` - Supprimer une collection (soft-delete avec `deleted_at`)
- `UpdateCollection` - Mettre à jour le titre
- `AddFeedToCollection` - Ajouter un podcast à une collection
- `RemoveFeedFromCollection` - Retirer un podcast d'une collection

**Événements CQRS** :
- `CollectionCreated` - Collection créée
- `CollectionDeleted` - Collection supprimée (soft-delete)
- `CollectionUpdated` - Titre mis à jour
- `FeedAddedToCollection` - Podcast ajouté
- `FeedRemovedFromCollection` - Podcast retiré

**Agrégat** :
- `User` aggregate - Gère l'état des collections utilisateur
- Validation : empêcher suppression collections avec podcasts

**Projections** :
- `collections` - Liste des collections (id, user_id, title, deleted_at, timestamps)
- `collection_subscriptions` - Jointure collections ↔ podcasts

**Base de Données** :
- Table `collections` : id, user_id, title, deleted_at, inserted_at, updated_at
- Table `collection_subscriptions` : collection_id, rss_source_feed
- Indexes : user_id, unique (collection_id, rss_source_feed)
- Soft-delete avec `deleted_at` nullable

**Modules** :
- Commands: `CreateCollection`, `DeleteCollection`, `UpdateCollection`, `AddFeedToCollection`, `RemoveFeedFromCollection`
- Events: `CollectionCreated`, `CollectionDeleted`, `CollectionUpdated`, `FeedAddedToCollection`, `FeedRemovedFromCollection`
- Schemas: `Collection`, `CollectionSubscription`
- Projector: `CollectionsProjector`

**Dispatcher** :
- Tous les commands routés via `Dispatcher.dispatch/1`
- Routage centralisé dans `dispatcher/router.ex`

**Migration** :
- `20251209000003_create_collections.exs` - Création tables collections et collection_subscriptions

---

### Subscription Pages Refactoring (v1.3)

Consolidation des pages d'abonnement.

**Navigation** :
- `/subscriptions/:feed` → **redirige vers `/podcasts/:feed`** (page publique consolidée)
- `/subscriptions` reste pour lister tous les abonnements
- `/subscriptions/new` reste pour ajouter
- Export OPML reste à `/subscriptions/export.opml`

**UI Conditionnelle sur Pages Publiques** :

Non authentifié :
- Bouton "Subscribe" → modal login inline
- Après login → redirige vers `/podcasts/:feed`

Authentifié + non abonné :
- Bouton "Subscribe" (action rapide) : POST `/podcasts/:feed/subscribe`
- "Add Custom RSS" : modal pour saisir URL manuelle

Authentifié + abonné :
- Bouton "Unsubscribe" : DELETE `/podcasts/:feed/subscribe` avec confirmation
- "Manage Subscriptions" : lien vers `/subscriptions`

**Routes** :
- `POST /podcasts/:feed/subscribe` - Subscribe rapide
- `DELETE /podcasts/:feed/subscribe` - Unsubscribe
- `GET /subscriptions/:feed` - Redirige vers `/podcasts/:feed`

---

## 🎙️ Découverte Publique

### Trending & Public Pages

Pages publiques accessibles à tous (pas d'authentification).

**Pages** :
- `GET /trending/podcasts` - Top 10 des podcasts par popularité
- `GET /trending/episodes` - Top 10 des épisodes par popularité
- `GET /podcasts/:feed` - Page publique d'un podcast avec :
  - Titre, couverture, description
  - Episodes récents
  - Boutons subscribe/unsubscribe (contextuels)
- `GET /episodes/:item` - Page publique d'un épisode avec :
  - Titre, description, durée
  - Statistiques (play count)

**Modules** :
- `PublicController` - Pages publiques
- `TrendingProjector` - Calcul popularité

**Popularité** :
- Basée sur nombre de plays enregistrés
- Mis à jour async par background workers
- Feed-level et episode-level

---

## 📻 Playback & Tracking

### Play Gateway avec Auto-token (v1.1+)

Système de tracking des écoutes via play gateway.

**Tokens Automatiques** :
- "Balados Web" créé automatiquement au premier accès à subscription
- Stocké dans `system.play_tokens` (données permanentes)
- Génération : 32 bytes aléatoires → Base64url (43 caractères)
- Unique par user + name
- Race condition handling via unique constraint

**Modes Flexibles** :

Production (external domain) :
```
https://{play_domain}/{token}/{feed}/{item}
config :balados_sync_web, play_domain: "play.example.com"
```

Développement (local path, défaut) :
```
/play/{token}/{feed}/{item}
# Aucune configuration requise
```

**URLs** :
- Constructeur : `PlayTokenHelper.build_play_url/3`
- Retourne soit URL externe soit path relatif selon config

**Tracking** :
- Tous les liens d'enclosure dans templates utilisent play gateway
- Liens automatiquement transformés dans RSS agrégé

**Modules** :
- `PlayTokenHelper` - Gestion tokens
- `PlayToken` schema (system repo)
- Routes `/play/:token/:feed/:item` (path mode)

### Live WebSocket Gateway (v1.2)

WebSocket standard pour communication temps réel.

**WebSocket Standard** :
- Pas Phoenix Channels (librairie spécifique)
- Implémente WebSock behaviour (standard Elixir)
- Compatible JS vanilla et apps tierces

**Authentification Duale** :

PlayToken :
- Simple bearer token (32 bytes B64url)
- Pas d'expiration (peut être revoked via `revoked_at`)

JWT AppToken :
- Full JWT avec scopes
- Expiration standard

Détection automatique du type de token.

**State Management** :
- Connexion commence en `:unauthenticated`
- Transition à `:authenticated` après validation du premier message
- Seul `{"type": "auth"}` accepté avant auth
- État persistent pendant la connexion

**Message Format** (JSON) :

Auth :
```json
{"type": "auth", "token": "xxx"}
```

Record Play :
```json
{
  "type": "record_play",
  "feed": "base64_encoded_feed",
  "item": "base64_encoded_item",
  "position": 123,
  "played": false
}
```

Responses :
```json
{"status": "ok", "message": "...", "data": {...}}
{"status": "error", "error": {"message": "...", "code": "..."}}
```

**Routes** :
- Production (subdomain) : `GET /api/v1/live` (host: "sync.")
- Production (path) : `GET /sync/api/v1/live`
- Développement : `ws://localhost:4000/sync/api/v1/live`

**Modules** :
- `LiveWebSocket.State` - État de connexion
- `LiveWebSocket.Auth` - Authentification
- `LiveWebSocket.MessageHandler` - Parsing/validation
- `LiveWebSocket` - Handler WebSocket
- `LiveWebSocketController` - HTTP upgrade

**Intégration CQRS** :
- Dispatch synchrone via `Dispatcher.dispatch(RecordPlay)`
- Réutilise `AppAuth.verify_app_request/1` pour JWT
- Réutilise `PlayToken` schema et validation
- Updates `last_used_at` async (Task.start)

---

## 🔐 Gestion de la Confidentialité

### Privacy Choice Modal (v1.4)

Modal de choix de confidentialité au premier abonnement/lecture.

**Niveaux de Confidentialité** :

- **Privé** : Aucun partage public, pas d'événement WebSocket
- **Anonyme** : Contribue aux statistiques sans révéler l'identité
- **Public** : Visible dans la découverte avec attribution

**Portée par Podcast** :
- Stockage dans `user_privacy` (feed-level, pas item-level)
- Une seule question par podcast
- Cache client pour éviter vérifications répétées
- Choix persistent entre sessions

**Intégration Subscribe & Play** :

Subscribe :
- Modal bloque le formulaire jusqu'au choix
- Empêche création abonnement sans privacy choisi

Play :
- Fire-and-forget non-bloquant
- Link ouvre immédiatement
- Privacy check en background

**Routes** (session-authenticated) :
- `GET /privacy/check/:feed` - Vérifier si privacy set → `{has_privacy: bool, privacy: level}`
- `POST /privacy/set/:feed` - Définir privacy niveau

**Commandes CQRS** :
- `ChangePrivacy` dispatch depuis WebPrivacyController
- `user_id`, `rss_source_feed`, `privacy` (atom)
- `event_infos` : device_id, device_name
- Émet `PrivacyChanged` event

**Modules** :
- `WebPrivacyController` - Endpoints session-authenticated
- `PrivacyManager` (TS) - Gestion centralisée côté client
- `SubscribeFlowHandler` (TS) - Interception subscribe
- `privacy_modal` component - UI modale

**Frontend** :
- Cache en mémoire par feed
- Communication avec serveur
- 3 boutons avec icônes et descriptions
- Responsive Tailwind
- Support clavier (Escape, Tab, focus)
- Intégration dans `dispatch_events.ts` pour WebSocket

### Public Timeline Page with Activity Feed (v1.7)

Page publique affichant un flux d'activité en temps réel de la communauté.

**Page** :
- Route : `GET /timeline` (public, pas d'authentification)
- Affiche flux des 50 derniers événements (subscribe/unsubscribe/play)
- Pagination avec Previous/Next buttons (limit/offset parameters)

**Événements Affichés** :
- **Subscription** : "X subscribed to Podcast Name" (bordure verte)
- **Play** : "X listened to Podcast Name" (bordure bleue)
- **Unsubscribe** : "X unsubscribed from Podcast Name" (bordure rouge)

**Enrichissement** :
- Métadonnées RSS en temps réel (titre, couverture)
- Cache 5 min pour éviter N+1 fetches
- Fallback "Unknown Podcast" si fetch échoue
- Couvertures manquantes : placeholder image

**Privacy Respecting** :
- Utilisateurs anonymes : affichent "Anonymous"
- LEFT JOIN pour masquer les utilisateurs privés
- Aucune exposition d'identifiants

**Routes & API** :
- `GET /timeline` - Afficher flux avec pagination
- `GET /timeline?limit=50&offset=0` - Pagination parameters

**Backend Modules** :
- `PublicController.timeline_html/2` - Query + pagination
- `PublicHTML.event_border_color/1` - Couleur bordure par type
- `PublicHTML.display_username/1` - Masquage anonyme
- `PublicHTML.event_action_text/1` - Verbe action
- `PublicHTML.podcast_title/1` - Titre fallback

**Frontend (v1.7.1)** :
- Client-side filtering par type d'événement
- Toast notifications au chargement
- Buttons "All Events", "Subscriptions", "Plays", "Unsubscribes"
- Auto-dismiss toasts après 5 secondes
- Filtrage en temps réel sans rechargement serveur

**Frontend Modules** :
- `timeline_filter.ts` - Gestion du filtrage client
- `toast_notifications.ts` - Système de notifications toast
- `app.ts` - Import des modules

**Fichiers** :
- `controllers/public_html/timeline.html.heex` - Template timeline
- `assets/js/timeline_filter.ts` - Filtrage par type
- `assets/js/toast_notifications.ts` - Toast notifications

**CQRS** :
- Read-only feature (pas de commands/events)
- Utilise projection existante : `PublicEvent`
- Aucune mutation sur event store

**Avantages** :
- Découverte communautaire : voir quels podcasts populaires les gens écoutent
- Privacy-respecting : anonymes masquées, utilisateurs privés non affichés
- Real-time enrichment : titres et couvertures fraîches via RssCache (5 min TTL)
- Scalable : pagination simple et requête optimisée avec indices DB

---

### Privacy Manager Page (v1.5)

**Page** :
- Route : `GET /privacy-manager` (authenticated only)
- Accessible via lien "Privacy" dans top bar (visible users authentifiés)

**Vue Centralisée** :
- Groupement en 3 sections : Public, Anonymous, Private
- Chaque section affiche :
  - Icône (bleu/violet/rouge)
  - Titre + compteur
  - Liste des podcasts
  - Empty state si vide
- Summary au bottom avec statistiques

**Fonctionnalités par Podcast** :

Lien clickable :
- Cover image ou placeholder cliquable → `/podcasts/:feed`
- Titre cliquable → `/podcasts/:feed`
- Hover effect (opacity-80)

Edit mode inline :
- Clic crayon → affiche controls
- Select dropdown (public/anonymous/private)
- "Change" button + "Cancel" link
- Fine ligne rouge séparant la section suppression
- "Remove" button → confirm → delete

**Interaction AJAX** :

Changement privacy :
- POST `/privacy-manager/:feed` avec `privacy` param
- Podcast se déplace entre sections immédiatement
- Pas de rechargement de page

Suppression :
- DELETE `/podcasts/:feed/subscribe` (réutilise endpoint public)
- Item retiré du DOM
- Compteurs mis à jour
- Empty state affiché si section vide

**Mises à Jour Dynamiques** :
- Compteurs (count badges)
- Summary counts (bottom stats)
- Empty states (show/hide)
- Tout en temps réel sans rechargement

**Modules** :
- `PrivacyManagerController` - CRUD privacy
  - `index/2` - Lister subscriptions groupées
  - `update_privacy/2` - Changer privacy level
- `PrivacyManagerHTML` - Embedding templates
- `privacy-manager-page.ts` - Event listeners AJAX

**Routes** :
- `GET /privacy-manager` - Liste groupée
- `POST /privacy-manager/:feed` - Changer privacy level
- `DELETE /podcasts/:feed/subscribe` - Supprimer abonnement

**Patterns** :
- **Groupement côté Server** : `Enum.group_by/2` par privacy level
- **Enrichissement** : Map feed_id → privacy level
- **Edit Mode** : Inline avec pencil icon
- **AJAX Detection** : Header `X-Requested-With` pour JSON vs HTML
- **DOM Updates** : Clone + reatach listeners + move entre sections

---

## 📊 Backend Infrastructure

### CQRS/Event Sourcing Pattern

**Core Commands** :
- `Subscribe` - Créer abonnement
- `Unsubscribe` - Supprimer abonnement
- `RecordPlay` - Enregistrer lecture
- `ChangePrivacy` - Changer niveau confidentialité

**Core Events** :
- `UserSubscribed`
- `UserUnsubscribed`
- `PlayRecorded`
- `PrivacyChanged`

**Aggregates** :
- `User` aggregate - State management utilisateur

**Projections** :
- `subscriptions` - Liste abonnements
- `user_privacy` - Niveaux confidentialité
- `plays` - Historique lectures
- `podcast_popularity` - Stats podcasts
- `episode_popularity` - Stats épisodes

**Eventual Consistency** :
- Projectors async
- Délai normal : quelques millisecondes
- Reset safe : `mix db.reset --projections`

### Architecture Multi-Repo

**SystemRepo** (schema: `system`) :
- Données permanentes : users, app_tokens, play_tokens
- Non event-sourced
- Commande : `mix system.migrate`

**ProjectionsRepo** (schema: `public`) :
- Projections event-sourcées
- Read models dénormalisés
- Reconstruisibles depuis events
- Commande : `mix projections.migrate`
- Reset safe : `mix db.reset --projections`

**EventStore** (schema: `events`) :
- Source de vérité immuable
- Géré par Commanded
- Jamais modifier manuellement

**Configuration Flexible** :

Même BDD, schemas différents (défaut dev) :
```elixir
config :balados_sync_projections, BaladosSyncProjections.SystemRepo,
  database: "balados_sync_dev"

config :balados_sync_projections, BaladosSyncProjections.ProjectionsRepo,
  database: "balados_sync_dev"
```

BDDs séparées (production) :
```elixir
config :balados_sync_projections, BaladosSyncProjections.SystemRepo,
  database: "balados_sync_system",
  hostname: "db-system.example.com"

config :balados_sync_projections, BaladosSyncProjections.ProjectionsRepo,
  database: "balados_sync_projections",
  hostname: "db-projections.example.com"
```

### Commandes de Développement

```bash
# Installation initiale
mix db.create     # Créer BDDs + event store
mix db.init       # Initialiser event store + migrer system

# Migration
mix db.migrate              # Tous les repos
mix system.migrate          # Seulement system
mix projections.migrate     # Seulement projections

# Reset (avec confirmation)
mix db.reset --projections  # ✅ SAFE - reset projections
mix db.reset --system       # ⚠️  DANGER - reset users/tokens
mix db.reset --events       # ☢️  EXTREME - reset event store
mix db.reset --all          # ☢️☢️ EXTREME - TOUT détruit
```

---

## 🎯 Frontend & UX

### Responsive Design

- Mobile-first avec Tailwind CSS
- Breakpoints standard (sm, md, lg, xl)
- Hover effects et transitions
- Animations minimalistes

### Progressive Enhancement

- Forms fonctionnent sans JavaScript (fallback serveur)
- AJAX améliore UX en évitant reloads
- Validation côté serveur + client

### Accessibility

- Modals avec support clavier (Escape, Tab, focus)
- ARIA labels sur buttons
- Contrast colors conformes WCAG
- Skip links si besoin

### TypeScript

- Tous les fichiers `.ts` (pas `.js`)
- Types interfaces pour DOM elements
- Strict mode activé

**Modules** :
- `app.ts` - Entry point, imports
- `privacy-manager-page.ts` - Privacy manager AJAX
- `privacy_manager.ts` - Privacy choice modal
- `subscribe_flow.ts` - Subscribe integration
- `dispatch_events.ts` - Play tracking WebSocket
- Autres modules utilitaires

---

## 📋 Checklist Implémentation Future

- [ ] Synchronisation temps réel multi-appareil
- [ ] Support applications mobiles (API)
- [ ] Fédération entre instances
- [ ] Découverte communautaire avancée
- [ ] Playlists collaboratives
- [ ] Historique d'écoute détaillé
- [ ] Recommandations personnalisées
- [ ] Partage de playlists
- [ ] Support formats additional (vidéo, etc.)

---

## 🔗 Documentation Associée

- [docs/GOALS.md](docs/GOALS.md) - Objectifs et vision
- [docs/technical/ARCHITECTURE.md](docs/technical/ARCHITECTURE.md) - Architecture système
- [docs/technical/DEVELOPMENT.md](docs/technical/DEVELOPMENT.md) - Workflow dev
- [docs/technical/AUTH_SYSTEM.md](docs/technical/AUTH_SYSTEM.md) - Système autorisation
- [docs/technical/CQRS_PATTERNS.md](docs/technical/CQRS_PATTERNS.md) - Patterns CQRS
- [docs/technical/DATABASE_SCHEMA.md](docs/technical/DATABASE_SCHEMA.md) - Schémas BD
