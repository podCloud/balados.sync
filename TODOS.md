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

### RSS Proxy hardening — fermer l'open proxy + (futur) proxy d'images HMAC

**Contexte / problème**
`GET /api/v1/rss/proxy/:encoded_feed_id` passe par le pipeline `:rss_api` qui **ne vérifie aucune auth** : l'endpoint est **public** et **ignore le JWT** envoyé par le front (`Authorization: Bearer`). C'est un **open proxy** (modulo SSRF déjà en place). Pas de rate limiting non plus.

**Décision d'architecture (issue de brainstorming) :**
- Le **HMAC ne sert PAS au feed XML.** Pour signer un feed arbitraire il faudrait que le client (PWA) détienne le secret → extractible → open proxy à nouveau. Le `fetch()` du feed **peut** porter le header → **enforcer le JWT suffit**.
- Le **HMAC ne sert QU'AUX images** : `<img>`/`<audio>` ne peuvent pas envoyer de header, donc la légitimité doit être **dans l'URL** (capability URL signée par le serveur).
- L'**audio (enclosures) n'est PAS proxifié** : proxifier l'audio centraliserait le trafic et **casserait les stats de download/écoute du podcasteur**. L'audio = consommation volontaire → reste en direct + (côté app) modal d'avertissement trackers au play/download. On ne proxifie que le **subi** (images qui se chargent toutes seules).

---

#### Phase A — MAINTENANT : enforcer le JWT sur le proxy du feed (ferme l'open proxy)

- [ ] Mettre `GET /api/v1/rss/proxy/:encoded_feed_id` (et `/:encoded_feed_id/:encoded_episode_id`) derrière l'auth JWT (scope `user.sync` ou équivalent), au lieu du pipeline `:rss_api` non authentifié.
- [ ] Ajouter un **rate limit par user** (réutiliser l'infra de #123 — rate limiting all API endpoints).
- [ ] Conserver tel quel : décodage base64url, validation SSRF (`UrlValidator`), cache Cachex 5 min.
- [ ] **Acceptance** : requête sans JWT → 401 ; avec JWT valide → feed proxifié ; dépassement quota → 429.

*Note front associée : l'app envoie déjà le JWT sur ce proxy ; côté serveur c'est purement de l'enforcement. Voir aussi la gestion du 401 côté app (ROADMAP balados.app).*

---

#### Phase B — FUTUR : proxy d'images HMAC (privacy / strip trackers show notes)

Bonus privacy à valeur marginale → **reporté**, design figé ci-dessous, à ressortir tel quel.

Pattern **capability-URL / endpoint de signature** (l'attribution/rate-limit se fait à l'émission JWT ; l'URL signée est **sans uid** donc partageable/cachable entre tous les users) :

- [ ] `POST /api/v1/rss/sign` — **JWT + rate-limit par user**. Body `{ feed }`. Valide SSRF. Renvoie `{ proxyUrl: "/api/v1/rss/proxy/{feedB64}?sig=HMAC(secret_serveur, feedB64)" }`. **Signature SANS uid.**
- [ ] `GET /api/v1/rss/proxy/{feedB64}?sig=...` — **pas de JWT, valide `sig`**. Fetch+cache le **XML brut** (partagé). Réécrit **toutes les URLs d'images** (artwork + `<img>` des show notes) en `/api/v1/rss/asset/{urlB64}?sig=HMAC(secret_serveur, urlB64)`. **Laisse les `<enclosure>` audio intactes.** Réécriture **déterministe** → réponse identique pour tous → cache partagé.
- [ ] `GET /api/v1/rss/asset/{urlB64}?sig=...` — **pas de JWT, valide `sig` + SSRF**. Fetch+cache l'image, sert. Chargeable en `<img>` sans header.
- [ ] **Signatures STABLES** (pas d'`exp` roulant) — sinon l'URL change à chaque refresh et casse le cache image 30 j du Service Worker. `exp` grossier/bucketisé (ex. arrondi au mois) seulement si défense en profondeur souhaitée.
- [ ] **Rotation du secret** = kill-switch global (incident).
- [ ] **Bornes d'abus** : rate-limit/user sur `/sign` + SSRF + rotation. **Résidu accepté** : une capability URL fuitée est réutilisable anonymement jusqu'à rotation (prix du `<img>` sans header).
- [ ] **Acceptance** : `/proxy` et `/asset` sans `sig` valide → 4xx ; deux users différents signant le même feed → **même URL** (cache partagé) ; enclosures audio inchangées dans le XML réécrit.

*Note : ne PAS cacher le XML déjà réécrit par user (le cache serveur est partagé) — cacher le brut, réécrire à la requête (déterministe).*

*Feature sœur (côté app, pas ici) : modal d'avertissement trackers au play/download — pendant « audio » de la même philosophie.*

---

## Issues Futures

Issues créées pour les fonctionnalités futures :

- [#153 - Playlists collaboratives](https://github.com/podCloud/balados.sync/issues/153)
- [#200 - Historique d'écoute détaillé](https://github.com/podCloud/balados.sync/issues/200)
- [#201 - Découverte communautaire avec recommandations MinHash](https://github.com/podCloud/balados.sync/issues/201)
- [#239 - Validate feed exists in collection before RemoveFeedFromCollection](https://github.com/podCloud/balados.sync/issues/239)
- [#240 - Explore per-command middleware when Commanded supports it](https://github.com/podCloud/balados.sync/issues/240)
- [#256 - String.to_existing_atom safety in LikeNormalizer](https://github.com/podCloud/balados.sync/issues/256)
- [#257 - Unbounded Like aggregate growth](https://github.com/podCloud/balados.sync/issues/257)
- [#258 - Checkpoint gap handling in LikeProjector](https://github.com/podCloud/balados.sync/issues/258)
- [#259 - Sync CQRS bypass for likes](https://github.com/podCloud/balados.sync/issues/259)
- [#260 - Private user tests for likes](https://github.com/podCloud/balados.sync/issues/260)

---

## In Progress

Format: `- [ ] Description - [#N](url) - STATUS`

- [ ] E2E UI testing with Wallaby - [#197](https://github.com/podCloud/balados.sync/issues/197) - PR [#198](https://github.com/podCloud/balados.sync/pull/198) - REVIEW

---

## Done

Format: `- [x] Description - [#N](url)`

- [x] Likes system (podcasts & episodes) - [#154](https://github.com/podCloud/balados.sync/issues/154) - PR #255
- [x] Split User aggregate into bounded contexts - [#148](https://github.com/podCloud/balados.sync/issues/148) - PR #238
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
