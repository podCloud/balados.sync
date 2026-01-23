# Task Queue

Sync tasks between this file and GitHub issues/PRs.

---

## Workflow for Claude Code

### Step 1: Fetch Current State

```bash
# List open issues
gh issue list --state open --json number,title,labels,state

# List open PRs
gh pr list --state open --json number,title,state,isDraft
```

### Step 2: Process TODO Section

For each task in TODO below:

1. Check if issue exists: `gh issue list --search "TASK_KEYWORDS"`
2. If not found, create it:

```bash
gh issue create \
  --title "feat: TITLE" \
  --body "## Objective
DESCRIPTION

## Context
WHY_IT_MATTERS

## Acceptance Criteria
- [ ] Implementation complete
- [ ] Tests pass"
```

3. Move task to "In Progress" with issue link

### Step 3: Update In Progress

For each item in "In Progress":

```bash
# Check issue/PR status
gh issue view NUMBER --json state,title
gh pr view NUMBER --json state,title,mergeable
```

Update status codes. Move merged PRs to "Done".

### Step 4: Commit Changes

```bash
git add TODOS.md
git commit --author="Claude <noreply@anthropic.com>" -m "chore: sync TODOS.md with GitHub"
git push
```

---

## Status Codes

| Code     | Meaning                    |
| -------- | -------------------------- |
| `OPEN`   | Issue created, not started |
| `WIP`    | PR in development          |
| `REVIEW` | PR awaiting review         |
| `MERGED` | Completed                  |

---

## TODO

Add tasks here. Claude will create GitHub issues for them.

(empty)

---

## Pending Issues to Create

Issues à créer par Claude Code Desktop (gh disponible).

### feat: Playlists collaboratives

**Labels:** `enhancement`

```markdown
## Objectif
Permettre à plusieurs utilisateurs de contribuer à une même playlist.

## Fonctionnalités potentielles
- Inviter des collaborateurs par username/email
- Permissions (view/edit/admin)
- Historique des modifications par collaborateur
- Notifications d'ajouts/modifications

## Questions ouvertes
- Modèle de permissions (simple ou granulaire ?)
- Limite de collaborateurs ?
- Modération du contenu ajouté ?

## Acceptance Criteria
- [ ] Inviter un collaborateur à une playlist
- [ ] Différents niveaux de permissions
- [ ] Collaborateurs peuvent ajouter/retirer des épisodes
- [ ] Propriétaire peut révoquer l'accès
- [ ] Tests couvrant les cas de permissions
```

### feat: Historique d'écoute détaillé

**Labels:** `enhancement`

```markdown
## Objectif
Page permettant de voir son historique d'écoute complet avec filtres et statistiques.

## Fonctionnalités potentielles
- Liste chronologique des écoutes
- Filtres par podcast, période, statut (terminé/en cours)
- Statistiques (temps total écouté, podcasts les plus écoutés)
- Export des données (CSV, JSON)

## Questions ouvertes
- Rétention des données (combien de temps garder l'historique ?)
- Granularité des statistiques ?
- Privacy : visible uniquement par l'utilisateur concerné

## Acceptance Criteria
- [ ] Page `/listening-history` accessible aux utilisateurs connectés
- [ ] Liste paginée des écoutes récentes
- [ ] Filtrage par podcast
- [ ] Statistiques de base (nombre d'épisodes, temps total)
- [ ] Tests de la page et des requêtes
```

### feat: Recommandations par collaborative filtering (MinHash)

**Labels:** `enhancement`

```markdown
## Objectif
Suggérer des podcasts basés sur les abonnements d'utilisateurs aux goûts similaires.

## Principe
"Les utilisateurs qui ont des abonnements similaires aux tiens écoutent aussi..."

## Architecture technique : MinHash + LSH

### Pourquoi MinHash ?
- Complexité O(n) vs O(n²) pour comparaison naïve
- Scalable dès le départ (pas de refactoring futur)
- Mémoire fixe par utilisateur (~512 bytes pour 128 hash)
- Approximation de Jaccard acceptable pour des recommandations (erreur < 5%)

### Algorithme MinHash
1. Générer K fonctions de hash (ex: K=128, fixées au démarrage)
2. Pour chaque utilisateur, calculer sa "signature" :
   - Pour chaque hash function, calculer min(hash(feed_url)) parmi ses abonnements
   - Résultat : vecteur de K valeurs (la signature)
3. Similarité entre 2 users ≈ % de signatures identiques

### Workflow
```
┌─────────────────────────────────────────────────────────────┐
│  Job périodique (toutes les 6h ou quotidien)                │
├─────────────────────────────────────────────────────────────┤
│  1. Charger abonnements publics                             │
│  2. Calculer signature MinHash par utilisateur              │
│  3. Pour chaque user, trouver les K voisins les plus        │
│     similaires (comparaison de signatures)                  │
│  4. Stocker dans table user_similarities                    │
└─────────────────────────────────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────────┐
│  GET /recommendations (temps réel)                          │
├─────────────────────────────────────────────────────────────┤
│  1. Récupérer les voisins précalculés                       │
│  2. Charger leurs abonnements publics                       │
│  3. Exclure ceux que le user a déjà                         │
│  4. Agréger par popularité parmi les voisins                │
│  5. Retourner top-10                                        │
└─────────────────────────────────────────────────────────────┘
```

### Stack technique
- Implémentation pure Elixir (pas besoin de Nx pour MinHash)
- Table `user_signatures` : user_id, signature (binary 512 bytes), updated_at
- Table `user_similarities` : user_id, similar_user_id, score

### Implémentation MinHash

#### 1. Hash functions (générées une fois, stockées en config)
```elixir
# K fonctions de hash : h(x) = (a * x + b) mod prime
@num_hashes 128
@prime 4_294_967_311  # Premier > 2^32

def generate_hash_functions do
  for _ <- 1..@num_hashes do
    {Enum.random(1..0xFFFFFFFF), Enum.random(0..0xFFFFFFFF)}
  end
end
```

#### 2. Calcul signature utilisateur
```elixir
def compute_signature(feed_urls, hash_fns) do
  Enum.map(hash_fns, fn {a, b} ->
    feed_urls
    |> Enum.map(fn url ->
      url_hash = :erlang.phash2(url, 0xFFFFFFFF)
      rem(a * url_hash + b, @prime)
    end)
    |> Enum.min(fn -> 0xFFFFFFFF end)
  end)
end
```

#### 3. Similarité entre signatures
```elixir
def similarity(sig1, sig2) do
  Enum.zip(sig1, sig2)
  |> Enum.count(fn {a, b} -> a == b end)
  |> Kernel./(length(sig1))
end
```

#### 4. Stockage binaire (512 bytes par user)
```elixir
def encode(sig), do: sig |> Enum.map(&<<&1::32>>) |> IO.iodata_to_binary()
def decode(bin), do: for <<val::32 <- bin>>, do: val
```

### LSH Banding avec Index Inversé SQL

Au lieu de comparer toutes les paires, on indexe les signatures par bandes en DB.

#### Schema SQL
```sql
CREATE TABLE user_band_buckets (
  user_id INT REFERENCES users(id),
  band_idx SMALLINT,      -- 0-63 (64 bandes de 2 valeurs)
  bucket_hash INT,        -- hash de la bande
  PRIMARY KEY (user_id, band_idx)
);

CREATE INDEX idx_bucket ON user_band_buckets(bucket_hash, band_idx);
```

#### Requête temps réel (< 50ms avec index)
```sql
SELECT other.user_id, COUNT(*) as shared_bands
FROM user_band_buckets mine
JOIN user_band_buckets other
  ON mine.bucket_hash = other.bucket_hash
  AND mine.band_idx = other.band_idx
WHERE mine.user_id = $1 AND other.user_id != $1
GROUP BY other.user_id
ORDER BY shared_bands DESC
LIMIT 20;
```

#### Pourquoi ça scale
- Pas de comparaison O(n²) - utilisation de l'index SQL B-tree
- Hash 32 bits → 4 milliards de buckets possibles
- Seuls les candidats similaires sont joints

### Estimation ressources (100k users × 500 abos max)

| Métrique | Valeur |
|----------|--------|
| Table `user_band_buckets` | 6.4M lignes (~80 MB) |
| Index `bucket_hash` | ~50 MB |
| Calcul initial signatures | ~2 min (parallélisé) |
| Requête temps réel | < 50ms |

### Deux types de recommandations

Pour éviter le "cold start problem" (nouveaux podcasts jamais recommandés), on sépare :

| Type | Description | Score |
|------|-------------|-------|
| **Mainstream** | Podcasts populaires que tu ne connais pas | `neighbor_ratio × log(total_subscribers)` |
| **Pépite** | Podcasts niche avec forte affinité | `neighbor_ratio / log(total_subscribers)` |

#### Calcul des scores
```elixir
def recommendation_scores(podcast, user_neighbors) do
  # % de mes voisins abonnés à ce podcast
  neighbor_ratio = neighbors_subscribed / total_neighbors

  # Abonnés totaux (tous utilisateurs confondus)
  total_subs = total_subscribers(podcast)

  %{
    mainstream: neighbor_ratio * :math.log(max(total_subs, 2)),
    niche: neighbor_ratio / :math.log(max(total_subs, 2))
  }
end
```

#### Freshness boost
Bonus temporaire pour les podcasts récemment découverts :
```elixir
def freshness_boost(podcast) do
  case days_since(podcast.first_subscribed_at) do
    d when d < 7 -> 1.5   # Découvert cette semaine
    d when d < 30 -> 1.2  # Découvert ce mois
    _ -> 1.0
  end
end
```

#### Affichage
```
📈 Populaires que tu pourrais aimer
   • Podcast A (1.2k abonnés, 8/20 voisins)
   • Podcast B (800 abonnés, 6/20 voisins)

💎 Pépites à découvrir
   • Podcast X (12 abonnés, 4/20 voisins) ← 33% affinité !
   • Podcast Y (28 abonnés, 3/20 voisins)
```

## Privacy
- Abonnement public = opt-in implicite pour les recommandations
- Ne jamais exposer "qui" a recommandé quoi
- Résultats agrégés uniquement

## Acceptance Criteria
- [ ] Module MinHash (hash functions, signatures, similarité)
- [ ] Table `user_band_buckets` avec index
- [ ] Job de précalcul des bandes (BaladosSyncJobs)
- [ ] Requête SQL optimisée pour trouver les voisins
- [ ] Scoring mainstream vs pépite
- [ ] Freshness boost pour nouveaux podcasts
- [ ] Endpoint `/recommendations` avec les deux sections
- [ ] Page web affichant les suggestions (2 sections)
- [ ] Performance < 50ms pour requête temps réel
- [ ] Tests unitaires MinHash (propriétés Jaccard)
- [ ] Tests de charge (simulation 100k users)
```

### feat: Découverte communautaire améliorée

**Labels:** `enhancement`

```markdown
## Objectif
Améliorer les pages de découverte existantes tout en restant un simple annuaire (pas de vampirisation de contenu).

## Philosophie
- Minimum d'infos stockées sur les podcasts (titre + feed URL uniquement)
- Pointer vers les sources, pas les copier
- Respecter le trafic des créateurs de podcasts

## Fonctionnalités

### 1. Recherche par titre
- Recherche dans les titres des podcasts connus (via subscriptions)
- Résultats limités aux podcasts ayant au moins 1 abonné public

### 2. Trending amélioré
- Filtres par période : aujourd'hui / cette semaine / ce mois
- Distinction podcasts vs épisodes
- Pagination

### 3. Nouveaux podcasts populaires
- Podcasts récemment découverts par la communauté
- Basé sur first_subscribed_at ou activité récente
- "Découvert cette semaine" / "Découvert ce mois"

## Données utilisées
- Uniquement ce qu'on a déjà : feed_url, title, activités (plays, subscribes)
- Pas de description, pas de catégories, pas de métadonnées enrichies

## Acceptance Criteria
- [ ] Recherche par titre fonctionnelle
- [ ] Filtres temporels sur /trending
- [ ] Page "Nouveaux podcasts" basée sur découverte récente
- [ ] Tests pour chaque fonctionnalité
```

---

## In Progress

Format: `- [ ] Description - [#N](url) - STATUS`

- [ ] E2E UI testing with Wallaby - [#197](https://github.com/podCloud/balados.sync/issues/197) - PR [#198](https://github.com/podCloud/balados.sync/pull/198) - REVIEW

---

## Done

Format: `- [x] Description - [#N](url)`

- [x] Extended OPML format with balados namespace - [#195](https://github.com/podCloud/balados.sync/issues/195) - PR #196
- [x] Document playlist type field and queue feature - [#185](https://github.com/podCloud/balados.sync/issues/185) - PR #194
- [x] Add ProjectorTestCase for CQRS/ES projector testing - [#191](https://github.com/podCloud/balados.sync/issues/191) - PR #193
- [x] Fix web tests DBConnection.OwnershipError - [#188](https://github.com/podCloud/balados.sync/issues/188) - PR #190
- [x] Add command-level validation for playlist_type - [#184](https://github.com/podCloud/balados.sync/issues/184) - PR #186
- [x] Fix user_test.exs MapSet.member? issue - [#187](https://github.com/podCloud/balados.sync/issues/187) - PR #189
- [x] Device playback queues using playlist system - [#182](https://github.com/podCloud/balados.sync/issues/182) - PR #183
- [x] Add property-based tests with StreamData - [#139](https://github.com/podCloud/balados.sync/issues/139) - PR #143
- [x] Migrate password hashing from bcrypt to Argon2id - [#138](https://github.com/podCloud/balados.sync/issues/138) - PR #142
- [x] Add machine-readable error codes to API responses - [#136](https://github.com/podCloud/balados.sync/issues/136) - PR #137
- [x] Add request body size limits to prevent memory exhaustion - [#133](https://github.com/podCloud/balados.sync/issues/133) - PR #134
- [x] Implement playlist sync in API endpoint - [#131](https://github.com/podCloud/balados.sync/issues/131) - PR #132
- [x] Sanitize error messages to prevent information leakage - [#124](https://github.com/podCloud/balados.sync/issues/124) - PR #130
- [x] Extend rate limiting to all API endpoints - [#123](https://github.com/podCloud/balados.sync/issues/123) - PR #129
- [x] Add input validation for RSS feed URLs (SSRF prevention) - [#122](https://github.com/podCloud/balados.sync/issues/122) - PR #128
- [x] Add comprehensive tests for PrivacyController - [#121](https://github.com/podCloud/balados.sync/issues/121) - PR #127
- [x] Admin Panel pour Flux Enrichis - [#26](https://github.com/podCloud/balados.sync/issues/26) - via PRs #107, #110, #112
- [x] Integration tests for email verification - [#116](https://github.com/podCloud/balados.sync/issues/116) - PR #118
- [x] Email verification for podcast ownership - [#69](https://github.com/podCloud/balados.sync/issues/69) - PR #112
- [x] Podcast ownership via RSS verification code - [#68](https://github.com/podCloud/balados.sync/issues/68) - PR #110
- [x] Enriched podcasts with slugs, branding, social links - [#65](https://github.com/podCloud/balados.sync/issues/65) - PR #107
- [x] Public user profile page - [#66](https://github.com/podCloud/balados.sync/issues/66) - PR #108
- [x] Public visibility toggle for playlists and collections - [#67](https://github.com/podCloud/balados.sync/issues/67) - PR #109
- [x] Dynamic RSS metadata enrichment for playlists - [#29](https://github.com/podCloud/balados.sync/issues/29) - PR #106
- [x] TypeScript test infrastructure for timeline_actions_menu - [#100](https://github.com/podCloud/balados.sync/issues/100) - PR #102
- [x] Timeline filter TypeScript tests - [#96](https://github.com/podCloud/balados.sync/issues/96) - PR #103
- [x] Optimize N+1 query in PlaylistsController - [#98](https://github.com/podCloud/balados.sync/issues/98) - PR #104
- [x] Audit logging for playlist operations - [#99](https://github.com/podCloud/balados.sync/issues/99) - PR #105
- [x] Timeline actions 3-dot menu - [#22](https://github.com/podCloud/balados.sync/issues/22) - PR #90
- [x] Toast notifications accessibility - [#52](https://github.com/podCloud/balados.sync/issues/52) - PR #93
- [x] Collections: reorder feeds - [#51](https://github.com/podCloud/balados.sync/issues/51) - PR #95
- [x] Playlists UI and CRUD - [#28](https://github.com/podCloud/balados.sync/issues/28) - PR #91
- [x] Persist timeline filter preferences - [#53](https://github.com/podCloud/balados.sync/issues/53) - PR #92
- [x] RSS aggregate feeds for collections/playlists - [#64](https://github.com/podCloud/balados.sync/issues/64) - PR #84
