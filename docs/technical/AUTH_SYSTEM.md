# Système d'Autorisation - Balados Sync

Ce document décrit en détail le système d'autorisation pour les applications tierces utilisant l'API Balados Sync.

## 📚 Table des Matières

- [Vue d'Ensemble](#vue-densemble)
- [Deux Types de Tokens](#deux-types-de-tokens)
- [Flux d'Autorisation OAuth-Style](#flux-dautorisation-oauth-style)
- [Système de Scopes](#système-de-scopes)
- [Validation JWT](#validation-jwt)
- [Image Visibility](#image-visibility)
- [Gestion des Autorisations](#gestion-des-autorisations)
- [API Reference](#api-reference)
- [Security Best Practices](#security-best-practices)

---

## Vue d'Ensemble

Balados Sync utilise un système d'autorisation **OAuth-style** avec JWT (RS256) pour permettre aux applications tierces d'accéder aux données utilisateurs de manière sécurisée et contrôlée.

### Principes

1. **App Identification** : Apps identifiées par `app_id` (du champ JWT `iss`)
2. **Public/Private Keys** : Signature asymétrique RS256
3. **Scopes Granulaires** : Permissions hiérarchiques avec wildcards
4. **User Control** : Utilisateurs contrôlent les permissions par app
5. **Revocation** : Révocation possible via web UI ou API

### Architecture

```
┌──────────────┐      1. Authorization JWT      ┌──────────────┐
│  Third-Party │ ─────────────────────────────> │   Balados    │
│     App      │                                 │     Sync     │
└──────────────┘                                 └──────────────┘
                                                        │
                                                        │ 2. User Approves
                                                        ▼
                                                 ┌─────────────┐
                                                 │ AppToken    │
                                                 │ Created     │
                                                 └─────────────┘
                                                        │
┌──────────────┐      3. API Request JWT              │
│  Third-Party │ ─────────────────────────────────────┘
│     App      │
└──────────────┘         4. Access Granted       ┌──────────────┐
       ▲                  (if scopes OK)         │   API Data   │
       └──────────────────────────────────────── │   Response   │
                                                 └──────────────┘
```

---

## Deux Types de Tokens

### 1. App Tokens (JWT-based)

**Usage** : API complète pour apps tierces

**Table** : `users.app_tokens`

**Authentification** : JWT RS256 signé avec clé privée de l'app

**Caractéristiques** :
- Scopes granulaires
- Révocable
- Public/private key pair
- App metadata (name, url, image)

### 2. Play Tokens (Bearer tokens)

**Usage** : Play gateway uniquement (track + redirect)

**Table** : `users.play_tokens`

**Authentification** : Simple bearer token

**Caractéristiques** :
- Pas de scopes (accès limité au play gateway)
- Révocable
- Plus simple pour intégrations basiques (RSS feeds)

---

## Flux d'Autorisation OAuth-Style

### Étape 1 : App Crée Authorization JWT

L'app crée un JWT contenant ses informations et sa **public key** :

```json
{
  "iss": "com.example.podcast-player",
  "app": {
    "name": "My Podcast Player",
    "url": "https://example.com",
    "image": "https://example.com/icon.png",
    "public_key": "-----BEGIN PUBLIC KEY-----\nMIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEA...\n-----END PUBLIC KEY-----"
  },
  "scopes": ["user.subscriptions.read", "user.plays.write"],
  "iat": 1732454400,
  "exp": 1732540800
}
```

**Signature** : JWT signé avec la **private key** de l'app (RS256)

**Tool** : Utiliser `/app-creator` page pour générer ce JWT facilement

### Étape 2 : Redirection Utilisateur

L'app redirige l'utilisateur vers :

```
https://balados.sync/authorize?token=eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9...
```

### Étape 3 : Validation par Balados Sync

Le serveur :
1. Décode le JWT
2. Extrait la **public key** du payload
3. **Vérifie la signature** du JWT avec cette public key
4. Valide les champs requis (`iss`, `app.name`, `app.public_key`, `scopes`)
5. Vérifie l'expiration

### Étape 4 : User Approval

L'utilisateur voit :
- Nom de l'app
- URL de l'app (lien cliquable)
- Image de l'app (si ≥10% users authorized)
- Liste des **scopes demandés** avec labels humains
- Stats d'utilisation

L'utilisateur peut :
- **Autoriser** : Crée/met à jour un `AppToken`
- **Refuser** : Redirige sans créer de token

### Étape 5 : App Makes API Requests

Après autorisation, l'app peut faire des requêtes API en créant des **API Request JWTs** :

```json
{
  "iss": "com.example.podcast-player",
  "sub": "user_abc123",
  "iat": 1732454400,
  "exp": 1732458000
}
```

**Signature** : JWT signé avec la **private key** de l'app

**Envoi** : Header `Authorization: Bearer <jwt_token>`

### Étape 6 : Validation API

Pour chaque requête API :
1. Extrait JWT du header
2. Extrait `iss` (app_id) et `sub` (user_id)
3. Cherche `AppToken` par `(user_id, app_id)`
4. Vérifie que l'app n'est pas révoquée
5. **Vérifie la signature** du JWT avec la **public_key** stockée
6. Vérifie les **scopes** requis par l'endpoint
7. Si OK : traite la requête
8. Sinon : 401 Unauthorized ou 403 Forbidden

---

## Système de Scopes

### Hiérarchie

Les scopes suivent une **hiérarchie en arbre** :

```
*                                    (full access)
├── *.read                           (read all)
├── *.write                          (write all)
└── user
    ├── user.read
    ├── user.write
    ├── user.subscriptions
    │   ├── user.subscriptions.read
    │   └── user.subscriptions.write
    ├── user.plays
    │   ├── user.plays.read
    │   └── user.plays.write
    ├── user.playlists
    │   ├── user.playlists.read
    │   └── user.playlists.write
    ├── user.likes
    │   ├── user.likes.read
    │   └── user.likes.write
    ├── user.privacy
    │   ├── user.privacy.read
    │   └── user.privacy.write
    └── user.sync
```

### Règles de Correspondance

Un scope **parent** accorde accès aux scopes **enfants** :

| Scope Accordé | Accorde Aussi |
|---------------|---------------|
| `*` | Tous les scopes |
| `*.read` | `user.subscriptions.read`, `user.plays.read`, ... |
| `user` | `user.read`, `user.write`, tous les sous-scopes |
| `user.subscriptions` | `user.subscriptions.read`, `user.subscriptions.write` |
| `user.subscriptions.read` | Uniquement ce scope |

### Wildcards

#### `*` - Full Access
Accorde **tous les scopes** possibles.

#### `*.read` - Read All
Accorde tous les scopes `.read` :
- `user.read`
- `user.subscriptions.read`
- `user.plays.read`
- `user.playlists.read`
- `user.likes.read`
- `user.privacy.read`

#### `*.write` - Write All
Accorde tous les scopes `.write`.

#### `user.*` - All User Scopes
Accorde tous les scopes commençant par `user.` :
- `user.subscriptions`
- `user.plays`
- `user.playlists`
- `user.privacy`
- `user.sync`

#### `user.*.read` - All User Read
Accorde tous les scopes `.read` sous `user`.

### Définitions Complètes

| Scope | Description |
|-------|-------------|
| `*` | Accès complet à toutes les données et opérations |
| `*.read` | Lecture complète de toutes les données |
| `*.write` | Écriture complète de toutes les données |
| `user` | Accès complet au profil utilisateur |
| `user.read` | Lire le profil utilisateur |
| `user.write` | Modifier le profil utilisateur |
| `user.subscriptions` | Accès complet aux abonnements |
| `user.subscriptions.read` | Lister les abonnements podcasts |
| `user.subscriptions.write` | Ajouter/supprimer des abonnements |
| `user.plays` | Accès complet aux statuts d'écoute |
| `user.plays.read` | Lire les positions et statuts d'écoute |
| `user.plays.write` | Mettre à jour positions et marquer comme écouté |
| `user.playlists` | Accès complet aux playlists |
| `user.playlists.read` | Lister les playlists et leur contenu |
| `user.playlists.write` | Créer, modifier, supprimer des playlists |
| `user.likes` | Accès complet aux likes (podcasts et épisodes) |
| `user.likes.read` | Lister les podcasts et épisodes likés |
| `user.likes.write` | Liker/unliker des podcasts et épisodes |
| `user.privacy` | Accès complet aux paramètres de confidentialité |
| `user.privacy.read` | Voir les paramètres de confidentialité |
| `user.privacy.write` | Modifier les paramètres de confidentialité |
| `user.sync` | Accès complet à la synchronisation (toutes données user) |

### Validation dans le Code

#### Module `Scopes`

```elixir
# apps/balados_sync_web/lib/balados_sync_web/scopes.ex

defmodule BaladosSyncWeb.Scopes do
  @doc "Vérifie si les scopes accordés permettent le scope requis"
  def authorized?(granted_scopes, required_scope) do
    Enum.any?(granted_scopes, fn granted ->
      scope_matches?(granted, required_scope)
    end)
  end

  @doc "Vérifie si TOUS les scopes requis sont accordés"
  def authorized_all?(granted_scopes, required_scopes) do
    Enum.all?(required_scopes, fn required ->
      authorized?(granted_scopes, required)
    end)
  end

  @doc "Vérifie si AU MOINS UN scope requis est accordé"
  def authorized_any?(granted_scopes, required_scopes) do
    Enum.any?(required_scopes, fn required ->
      authorized?(granted_scopes, required)
    end)
  end
end
```

#### JWTAuth Plug

```elixir
# apps/balados_sync_web/lib/balados_sync_web/plugs/jwt_auth.ex

# Require specific scopes (ALL must be granted)
plug JWTAuth, [scopes: ["user.subscriptions.read"]] when action in [:index]

# Require ANY of the scopes
plug JWTAuth, [scopes_any: ["user.sync", "user"]] when action in [:sync]
```

### Scopes par Endpoint

| Endpoint | Method | Scope(s) Requis |
|----------|--------|----------------|
| `/api/v1/subscriptions` | GET | `user.subscriptions.read` |
| `/api/v1/subscriptions` | POST | `user.subscriptions.write` |
| `/api/v1/subscriptions/:feed` | DELETE | `user.subscriptions.write` |
| `/api/v1/plays` | GET | `user.plays.read` |
| `/api/v1/plays` | POST | `user.plays.write` |
| `/api/v1/plays/:item/position` | PUT | `user.plays.write` |
| `/api/v1/playlists` | GET | `user.playlists.read` |
| `/api/v1/playlists` | POST | `user.playlists.write` |
| `/api/v1/playlists/:id` | PUT/DELETE | `user.playlists.write` |
| `/api/v1/likes` | GET | `user.likes.read` |
| `/api/v1/likes` | POST | `user.likes.write` |
| `/api/v1/likes` | DELETE | `user.likes.write` |
| `/api/v1/privacy` | GET | `user.privacy.read` |
| `/api/v1/privacy` | PUT | `user.privacy.write` |
| `/api/v1/sync` | POST | `user.sync` OR `user` |
| `/api/v1/apps` | GET | Any valid token |
| `/api/v1/apps/:app_id` | DELETE | Any valid token |

---

## Validation JWT

### Processus de Vérification

#### Authorization JWT (Step 1-4)

```elixir
def decode_app_token(token) do
  with {:ok, claims} <- Joken.peek_claims(token),
       {:ok, app_id} <- extract_app_id(claims),          # "iss"
       {:ok, public_key} <- extract_public_key(claims),  # "app.public_key"
       {:ok, verified_claims} <- verify_with_public_key(token, public_key) do
    {:ok, verified_claims}
  else
    {:error, reason} -> {:error, reason}
  end
end
```

**Points clés** :
- Public key est **dans le JWT payload**
- On vérifie le JWT **avec cette public key**
- Empêche la falsification (sans private key, impossible de signer correctement)

#### API Request JWT (Step 5-6)

```elixir
def verify_app_request(token) do
  with {:ok, claims} <- Joken.peek_claims(token),
       {:ok, app_id} <- extract_app_id(claims),           # "iss"
       {:ok, user_id} <- extract_user_id(claims),         # "sub"
       {:ok, app_token} <- get_active_token(user_id, app_id),
       {:ok, verified_claims} <- verify_with_public_key(token, app_token.public_key) do
    {:ok, %{claims: verified_claims, app_token: app_token}}
  else
    {:error, reason} -> {:error, reason}
  end
end
```

**Points clés** :
- Cherche l'autorisation par `(user_id, app_id)`
- Utilise la **public_key stockée** lors de l'autorisation
- Vérifie le JWT avec cette key
- Retourne les scopes accordés

### Sécurité de la Signature

**Principe** :
1. App génère une paire RSA (2048+ bits)
2. App garde la **private key secrète**
3. App inclut la **public key** dans authorization JWT
4. Server stocke la public key lors de l'autorisation
5. Server vérifie tous les futurs JWTs avec cette public key

**Garanties** :
- Seule l'app avec la private key peut créer des JWTs valides
- Public key ne permet QUE la vérification, pas la création
- Impossible de forger un JWT sans la private key

---

## Image Visibility

### Règle

Les images d'apps ne sont affichées que si **≥10% des utilisateurs** ont autorisé l'app.

### Rationale

- Protège contre le spam/phishing
- Apps légitimes atteignent naturellement ce seuil
- Encourage la qualité et la confiance

### Calcul

```elixir
def get_app_usage_stats(app_id, public_key) do
  # Nombre d'utilisateurs ayant autorisé cette app
  user_count = count_users_for_app(app_id, public_key)

  # Nombre total d'utilisateurs
  total_users = count_total_users()

  # Pourcentage
  percentage = if total_users > 0 do
    (user_count / total_users) * 100.0
  else
    0.0
  end

  {user_count, percentage, total_users}
end
```

### Affichage

```elixir
def calculate_image_visibility(user_count, percentage, _total_users) do
  show_image = percentage >= 10.0

  user_display = cond do
    # Si < 1%, afficher nombre arrondi à la dizaine
    percentage < 1.0 ->
      rounded_count = div(user_count + 5, 10) * 10
      "~#{rounded_count} users"

    # Sinon afficher pourcentage arrondi supérieur
    true ->
      rounded_percentage = ceil(percentage)
      "#{rounded_percentage}% of users"
  end

  {show_image, user_display}
end
```

### Exemples

| Users | Total | % | Image Shown? | Display |
|-------|-------|---|--------------|---------|
| 5 | 1000 | 0.5% | ❌ Non | "~10 users" |
| 45 | 1000 | 4.5% | ❌ Non | "5% of users" |
| 99 | 1000 | 9.9% | ❌ Non | "10% of users" |
| 100 | 1000 | 10% | ✅ Oui | "10% of users" |
| 150 | 1000 | 15% | ✅ Oui | "15% of users" |

---

## Gestion des Autorisations

### Update vs Create

Quand un utilisateur autorise une app **déjà autorisée** :
- Le système **met à jour** l'autorisation existante
- Les nouveaux scopes **remplacent** les anciens
- Permet de modifier les permissions sans créer de doublon

```elixir
def authorize_app(user_id, decoded_data) do
  app_id = decoded_data["iss"]

  # Upsert : update si existe, insert sinon
  AppToken.changeset(%AppToken{}, %{
    user_id: user_id,
    app_id: app_id,
    scopes: decoded_data["scopes"],
    # ...
  })
  |> Repo.insert(
    on_conflict: {:replace_all_except, [:id, :inserted_at]},
    conflict_target: [:user_id, :app_id]
  )
end
```

### Révocation

#### Via Web Interface

```
GET /apps
→ Liste des apps autorisées
→ Bouton "Revoke Access" par app
```

#### Via API

```bash
DELETE /api/v1/apps/:app_id
Authorization: Bearer <user_jwt>
```

**Effet** :
- `revoked_at` = timestamp actuel
- Tous les futurs JWTs de cette app pour cet user = refusés
- L'app peut **ré-autoriser** (nouveau flow complet)

---

## API Reference

### POST /authorize

**Description** : Créer une autorisation après user approval

**Body** :
```json
{
  "token": "eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9..."
}
```

**Response 200** :
```json
{
  "status": "success",
  "message": "Application authorized successfully"
}
```

**Errors** :
- 400 : Token invalide
- 401 : User non authentifié
- 422 : Validation error (champs manquants, etc.)

### GET /api/v1/apps

**Description** : Lister les apps autorisées par le user

**Auth** : JWT token required

**Response 200** :
```json
{
  "apps": [
    {
      "id": "uuid",
      "app_id": "com.example.podcast-player",
      "app_name": "Podcast Player Pro",
      "app_url": "https://podcastplayer.com",
      "app_image": "https://podcastplayer.com/icon.png",
      "scopes": ["user.subscriptions.read", "user.plays.write"],
      "last_used_at": "2025-11-24T10:30:00Z",
      "inserted_at": "2025-11-01T08:00:00Z",
      "updated_at": "2025-11-20T15:45:00Z"
    }
  ]
}
```

### DELETE /api/v1/apps/:app_id

**Description** : Révoquer une autorisation

**Auth** : JWT token required

**Response 200** :
```json
{
  "status": "success",
  "message": "App authorization revoked"
}
```

**Response 404** :
```json
{
  "error": "App not found or already revoked"
}
```

---

## Security Best Practices

### Pour les Développeurs d'Apps

#### 1. Garder les Private Keys Secrètes
```bash
# ❌ NE JAMAIS commit
private_key.pem

# ✅ Utiliser des variables d'environnement
export APP_PRIVATE_KEY="$(cat private_key.pem)"
```

#### 2. Demander le Minimum de Scopes
```json
// ❌ Trop de permissions
"scopes": ["*"]

// ✅ Seulement ce qui est nécessaire
"scopes": ["user.subscriptions.read", "user.plays.write"]
```

#### 3. Tokens Courte Durée
```json
// API request tokens : 1 heure max
{
  "iat": 1732454400,
  "exp": 1732458000  // +1 hour
}

// Authorization tokens : 24 heures max
{
  "iat": 1732454400,
  "exp": 1732540800  // +24 hours
}
```

#### 4. Gérer les Erreurs Proprement
```javascript
try {
  const response = await fetch('/api/v1/subscriptions', {
    headers: { 'Authorization': `Bearer ${jwt}` }
  });

  if (response.status === 403) {
    // Scope insuffisant → redemander autorisation avec plus de scopes
  } else if (response.status === 401) {
    // Token invalide/expiré → renouveler le JWT
  }
} catch (error) {
  // Handle network errors
}
```

#### 5. Rotation des Keys (Production)
- Rotate keys périodiquement (ex: tous les 6 mois)
- Support de plusieurs public keys simultanément (transition period)
- Invalider les anciennes keys après transition

### Pour l'Infrastructure Balados Sync

#### 1. HTTPS Obligatoire en Production
```elixir
# config/prod.exs
config :balados_sync_web, BaladosSyncWeb.Endpoint,
  force_ssl: [rewrite_on: [:x_forwarded_proto]],
  url: [scheme: "https", host: "balados.sync", port: 443]
```

#### 2. Rate Limiting
```elixir
# Limiter les tentatives d'autorisation
plug :rate_limit, max_requests: 10, interval: :timer.minutes(1)
```

#### 3. Monitoring
- Logger toutes les tentatives d'auth échouées
- Alertes si spike de 401/403
- Métriques d'utilisation par app

#### 4. Key Validation Stricte
- Minimum 2048 bits pour RSA keys
- Rejeter keys trop faibles
- Valider le format PEM

---

## Troubleshooting

### 401 Unauthorized

**Causes possibles** :
1. JWT signature invalide (mauvaise private key)
2. Token expiré (`exp` < maintenant)
3. App non autorisée (pas d'AppToken pour ce user/app)
4. App révoquée (`revoked_at` non-null)
5. Champs manquants (`iss` ou `sub`)

**Debug** :
```elixir
# Logger dans JWTAuth plug
Logger.debug("JWT validation failed: #{inspect(reason)}")
```

### 403 Forbidden

**Cause** : Scopes insuffisants

**Exemple** :
```
Endpoint: POST /api/v1/subscriptions
Required: ["user.subscriptions.write"]
Granted: ["user.subscriptions.read"]
→ 403 Forbidden
```

**Solution** : Redemander autorisation avec les bons scopes

### Authorization Token Rejected

**Causes possibles** :
1. Public key malformée dans le JWT
2. JWT pas signé avec la private key correspondante
3. Champs requis manquants (`iss`, `app.name`, `app.public_key`)
4. Scopes invalides (noms de scopes incorrects)

**Debug** :
```bash
# Décoder le JWT pour vérifier payload
# jwt.io ou :
echo "JWT_TOKEN" | cut -d'.' -f2 | base64 -d | jq
```

---

## Files Reference

### Key Files

- `apps/balados_sync_web/lib/balados_sync_web/app_auth.ex` : Authorization logic
- `apps/balados_sync_web/lib/balados_sync_web/scopes.ex` : Scope definitions & matching
- `apps/balados_sync_web/lib/balados_sync_web/plugs/jwt_auth.ex` : JWT validation plug
- `apps/balados_sync_projections/lib/balados_sync_projections/schemas/app_token.ex` : AppToken schema
- `apps/balados_sync_web/lib/balados_sync_web/controllers/app_auth_controller.ex` : Auth endpoints

### UI Pages

- `/app-creator` : Token generator tool
- `/authorize?token=...` : User authorization page
- `/apps` : Manage authorized apps

---

**Voir aussi** :
- [ARCHITECTURE.md](ARCHITECTURE.md) : Architecture globale
- [DEVELOPMENT.md](DEVELOPMENT.md) : Commandes de développement
- [docs/api/authentication.livemd](../api/authentication.livemd) : Documentation API détaillée
- [TESTING_GUIDE.md](../../TESTING_GUIDE.md) : Guide de tests du système d'auth

**Dernière mise à jour** : 2025-11-24
