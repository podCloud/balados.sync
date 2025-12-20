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

### Playlists CRUD Web UI (v2.0)

Interface web complète pour la gestion des playlists d'épisodes.

**Pages** :
- `GET /playlists` - Liste des playlists de l'utilisateur
- `GET /playlists/new` - Formulaire de création
- `POST /playlists` - Créer une playlist
- `GET /playlists/:id` - Détails d'une playlist avec ses épisodes
- `GET /playlists/:id/edit` - Formulaire de modification
- `PATCH /playlists/:id` - Modifier une playlist
- `DELETE /playlists/:id` - Supprimer une playlist (soft-delete)

**Commandes CQRS** :
- `CreatePlaylist` - Créer une playlist avec nom et description optionnelle
- `UpdatePlaylist` - Modifier nom et/ou description
- `DeletePlaylist` - Supprimer une playlist (soft-delete avec `deleted_at`)

**Événements CQRS** :
- `PlaylistCreated` - Playlist créée avec id généré
- `PlaylistUpdated` - Nom/description mis à jour
- `PlaylistDeleted` - Playlist supprimée (soft-delete)

**Agrégat** :
- `User` aggregate - Gère l'état des playlists utilisateur
- Validation : nom requis, empêcher création doublons par playlist_id

**Projections** :
- `playlists` - Liste des playlists (id, user_id, name, description, deleted_at, timestamps)
- `playlist_items` - Épisodes dans les playlists

**Base de Données** :
- Table `playlists` (schema `users`) : id, user_id, name, description, deleted_at, inserted_at, updated_at
- Table `playlist_items` (schema `users`) : id, playlist_id, rss_source_feed, rss_source_item, item_title, feed_title, position, deleted_at
- Indexes : user_id, playlist_id
- Soft-delete avec `deleted_at` nullable

**Modules** :
- Commands: `CreatePlaylist`, `UpdatePlaylist`, `DeletePlaylist`
- Events: `PlaylistCreated`, `PlaylistUpdated`, `PlaylistDeleted`
- Schemas: `Playlist`, `PlaylistItem`
- Projector: `PlaylistsProjector`
- Controller: `PlaylistsController`
- HTML: `PlaylistsHTML`

**Tests** :
- `user_playlists_test.exs` - Tests aggregate (CreatePlaylist, DeletePlaylist, event apply)
- `playlists_projector_test.exs` - Tests projector (create, delete, update events)

**Migrations** :
- `20251121000004_create_playlists.exs` - Création tables playlists et playlist_items
- `20251209000002_add_playlist_fields.exs` - Ajout champs additionnels
- `20251219101124_add_deleted_at_to_playlists.exs` - Support soft-delete

---

### Podcast Ownership & Verification (v2.3)

Système de vérification d'ownership de podcasts via code RSS.

**Flux de Vérification** :
1. L'utilisateur initie une revendication pour un podcast (URL du flux)
2. Le système génère un code de vérification unique
3. L'utilisateur ajoute le code n'importe où dans son flux RSS
4. L'utilisateur déclenche la vérification
5. Le système récupère le flux RSS brut (bypass cache) et recherche le code
6. Si trouvé, l'ownership est accordé
7. Le code peut être retiré du flux après vérification

**Pages** :
- `GET /podcast-ownership` - Liste des podcasts revendiqués et claims en attente
- `GET /podcast-ownership/new` - Formulaire de revendication
- `POST /podcast-ownership` - Initier une revendication
- `GET /podcast-ownership/claims/:id` - Instructions de vérification
- `POST /podcast-ownership/claims/:id/verify` - Déclencher vérification
- `POST /podcast-ownership/claims/:id/cancel` - Annuler claim
- `GET /podcast-ownership/podcasts/:id` - Gérer un podcast revendiqué
- `POST /podcast-ownership/podcasts/:id/visibility` - Changer visibilité
- `POST /podcast-ownership/podcasts/:id/relinquish` - Abandonner ownership

**Tables Système** :
- `enriched_podcasts` - Podcasts enrichis avec admin_user_ids (multi-admin)
- `podcast_ownership_claims` - Claims en cours de vérification
- `user_podcast_settings` - Préférences de visibilité par utilisateur

**Sécurité** :
- Code format: `balados-verify-<random_hex_32>` (cryptographiquement sécurisé)
- Expiration: 48 heures par défaut
- Rate limiting: max 5 tentatives par heure par utilisateur
- Fetch brut: bypass tous les caches, timeout 30s

**Multi-Admin** :
- Plusieurs utilisateurs peuvent vérifier et administrer le même podcast
- Chaque admin a ses propres paramètres de visibilité
- `admin_user_ids` stocke tous les admins

**Visibilité** :
- `public` - Apparaît sur le profil public de l'utilisateur
- `private` - N'apparaît pas publiquement

**Background Worker** :
- `OwnershipClaimCleanupWorker` - Expire les claims périmés, nettoie les vieux claims
- Exécution quotidienne à 3h UTC

**Modules** :
- Context: `PodcastOwnership` (non-CQRS, tables système)
- Controller: `PodcastOwnershipController`
- Schemas: `EnrichedPodcast`, `PodcastOwnershipClaim`, `UserPodcastSettings`
- Worker: `OwnershipClaimCleanupWorker`

**Migrations** :
- `20251220125001_create_enriched_podcasts.exs` - Table enriched_podcasts
- `20251220130001_add_podcast_ownership_tables.exs` - Tables claims et settings, admin_user_ids

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

### RSS Aggregate Feeds (v1.9)

Génération de flux RSS agrégés pour abonnements, collections et playlists.

**Routes** :
- `GET /rss/:play_token/subscriptions` - Flux agrégé de tous les abonnements
- `GET /rss/:play_token/collections/:collection_id` - Flux agrégé d'une collection
- `GET /rss/:play_token/playlists/:playlist_id` - Flux agrégé d'une playlist

> Note: L'extension `.xml` n'est pas supportée dans les paths dynamiques Phoenix.
> Le format est déterminé par le header `Accept`.

**Authentification** :
- PlayToken dans le path (pas en query param pour meilleure compatibilité)
- Validation de propriété (user_id du token = user_id de la ressource)
- Update automatique de `last_used_at` à chaque accès

**Fonctionnalités** :
- Fetch parallèle des feeds source via `Task.async_stream`
- Merge chronologique des épisodes (plus récent en premier)
- Limite de 100 épisodes par flux agrégé
- Transformation des URLs d'enclosure vers play gateway
- Titres enrichis : "Podcast Name - Episode Title"
- Cache HTTP : `private, max-age=60`

**Gestion d'Erreurs** :
- 401 Unauthorized : Token invalide ou révoqué
- 403 Forbidden : Accès à ressource d'un autre utilisateur
- 404 Not Found : Collection/playlist inexistante
- Feeds sources inaccessibles : skip silencieux avec logging

**Format RSS** :
- RSS 2.0 avec namespaces iTunes et Atom
- Métadonnées channel : titre, description, language, pubDate
- Items complets avec guid, title, description, enclosure, pubDate
- Échappement XML sécurisé

**Collections** :
- Titre du feed = titre de la collection
- Description du feed = description de la collection (ou titre par défaut)
- Fetch uniquement des subscriptions actives (non-unsubscribed)
- Join entre `collection_subscriptions` et `subscriptions`

**Playlists** :
- Titre du feed = nom de la playlist
- Description du feed = description de la playlist
- Fetch uniquement des items non-deleted
- Filtrage des épisodes par guid depuis les feeds source

**Modules** :
- `RssAggregateController` - Génération et routing
- `RssCache` - Cache des feeds source (5 min TTL)
- `PlayTokenHelper` - Validation et construction URLs

### Enriched Podcasts (v2.1)

Admin-managed podcast entries with custom slugs, branding, and social links.

**Features** :
- **Custom URL slugs** : Human-readable URLs (e.g., `/podcasts/my-show` instead of base64)
- **Branding** : Background color for podcast page theming
- **Social links** : Twitter/X, Mastodon, Instagram, YouTube, Spotify, Apple Podcasts
- **Custom links** : Add arbitrary links with custom titles
- **SEO redirect** : Base64 URLs automatically redirect to slug URLs

**Admin Interface** :
- `GET /admin/enriched-podcasts` - List all enriched podcasts
- `GET /admin/enriched-podcasts/new` - Create new enriched podcast
- `GET /admin/enriched-podcasts/:id` - View enriched podcast with stats
- `GET /admin/enriched-podcasts/:id/edit` - Edit enriched podcast
- `POST /admin/enriched-podcasts` - Create
- `PUT /admin/enriched-podcasts/:id` - Update
- `DELETE /admin/enriched-podcasts/:id` - Delete

**Public Access** :
- `/podcasts/:slug` - Access by custom slug
- `/podcasts/:base64` - Falls back to base64 (redirects to slug if enriched)
- Admin link on podcast page for quick access to enrichment

**Database** (System schema, not event-sourced) :
- Table `system.enriched_podcasts` : id, feed_url, slug, background_color, links (JSONB), created_by_user_id
- Unique indexes on slug and feed_url

**Validation Rules** :
- Slug: 3-50 lowercase letters, numbers, hyphens only
- Slug cannot look like base64 (no uppercase, +, /, =)
- Background color: valid hex format (#RRGGBB)
- Links: max 10, valid URLs, proper format

**Social Network Types** :
- `twitter` - Twitter/X with icon
- `mastodon` - Mastodon with icon
- `instagram` - Instagram with icon
- `youtube` - YouTube with icon
- `spotify` - Spotify with icon
- `apple_podcasts` - Apple Podcasts with icon
- `custom` - Custom link with title

**Modules** :
- Schema: `BaladosSyncProjections.Schemas.EnrichedPodcast`
- Context: `BaladosSyncWeb.EnrichedPodcasts`
- Controller: `BaladosSyncWeb.EnrichedPodcastsController`
- HTML: `BaladosSyncWeb.EnrichedPodcastsHTML`

**Integration** :
- Public podcast page displays enrichment (background color, links)
- Admin link on podcast page for quick enrichment creation/editing
- Automatic redirect from base64 to slug for SEO

---

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
- [x] Playlists CRUD de base (v2.0 ✅)
- [ ] Playlists collaboratives
- [ ] Historique d'écoute détaillé
- [ ] Recommandations personnalisées
- [x] Public visibility for playlists (v2.2 ✅)
- [ ] Public visibility for collections
- [ ] Shareable public URLs
- [ ] Support formats additional (vidéo, etc.)

---

## 👤 User Profiles

### Public User Profiles (v2.2)

Pages de profil utilisateur personnalisables et publiques.

**Pages** :
- `GET /u/:username` - Page de profil public (accessible à tous)
- `GET /settings/profile` - Édition du profil (authentifié)
- `PUT /settings/profile` - Mise à jour du profil (authentifié)

**Champs de Profil** :
- **public_name** : Nom d'affichage (optionnel, max 100 caractères)
- **bio** : Biographie courte (optionnel, max 500 caractères)
- **avatar_url** : URL d'avatar (optionnel, max 500 caractères)
- **public_profile_enabled** : Activer/désactiver le profil public (défaut: false)

**Fonctionnalités** :
- Display name prioritaire sur username si défini
- Avatar avec fallback vers initiale colorée
- Timeline d'activité récente (20 derniers événements publics)
- Liens vers pages podcasts depuis la timeline
- Privacy respecting : seuls les événements "public" sont affichés

**Timeline Utilisateur** :
- Affiche les écoutes récentes de l'utilisateur (privacy = "public")
- Enrichissement via RssCache (titre podcast, couverture)
- Format relatif pour les timestamps ("2h ago", "3d ago")
- Fallback "No public activity yet" si vide

**Sécurité** :
- Profil visible uniquement si `public_profile_enabled = true`
- Retourne 404 si utilisateur inexistant ou profil désactivé
- Pas d'exposition d'informations privées

**Base de Données** :
- Table `system.users` : ajout colonnes public_name, bio, avatar_url, public_profile_enabled
- Migration : `20251220100001_add_user_profile_fields.exs`

**Modules** :
- `ProfileController` - Contrôleur pour edit/update/show
- `ProfileHTML` - Helpers d'affichage (display_name, time_ago_in_words)
- `User.profile_changeset/2` - Validation des champs profil
- Templates: `edit.html.heex`, `show.html.heex`

**Tests** :
- `profile_controller_test.exs` - 13 tests couvrant :
  - Authentication enforcement (edit/update)
  - Profile settings form rendering
  - Profile update success/validation
  - Public profile visibility
  - 404 pour profils désactivés/inexistants

---

## 🌐 Public Visibility (v2.3)

### Playlist Public Visibility

Allows users to make their playlists publicly visible on their profile.

**CQRS Commands** :
- `ChangePlaylistVisibility` - Toggle playlist visibility (public/private)
- `ChangeCollectionVisibility` - Toggle collection visibility (public/private)

**CQRS Events** :
- `PlaylistVisibilityChanged` - Emitted when playlist visibility changes
- `CollectionVisibilityChanged` - Emitted when collection visibility changes

**Aggregate Updates** :
- User aggregate handles visibility commands
- State includes `is_public` flag per playlist/collection

**Projections** :
- `playlists.is_public` - Boolean flag (default: false)
- `collections.is_public` - Boolean flag (default: false)
- Indexes on `(user_id, is_public)` for efficient queries

**UI** :
- Toggle button on playlist show page
- Visual indicator (green for public, gray for private)
- Flash message on toggle

**Routes** :
- `POST /playlists/:id/toggle-visibility` - Toggle playlist visibility

**Migration** :
- `20251220120001_add_is_public_to_playlists_and_collections.exs`

---

## 🔗 Documentation Associée

- [docs/GOALS.md](docs/GOALS.md) - Objectifs et vision
- [docs/technical/ARCHITECTURE.md](docs/technical/ARCHITECTURE.md) - Architecture système
- [docs/technical/DEVELOPMENT.md](docs/technical/DEVELOPMENT.md) - Workflow dev
- [docs/technical/AUTH_SYSTEM.md](docs/technical/AUTH_SYSTEM.md) - Système autorisation
- [docs/technical/CQRS_PATTERNS.md](docs/technical/CQRS_PATTERNS.md) - Patterns CQRS
- [docs/technical/DATABASE_SCHEMA.md](docs/technical/DATABASE_SCHEMA.md) - Schémas BD
