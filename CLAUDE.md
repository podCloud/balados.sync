# CLAUDE.md - Balados Sync

Ce fichier fournit des instructions à Claude Code pour travailler sur ce repository.

## 📖 Vue d'Ensemble du Projet

**Balados Sync** est une plateforme ouverte de synchronisation de podcasts utilisant **CQRS/Event Sourcing** avec Elixir.

### Objectif Principal

Créer une plateforme ouverte pour synchroniser les écoutes de podcasts entre applications et appareils, avec découverte communautaire et support self-hosted.

**👉 Voir** : [docs/GOALS.md](docs/GOALS.md)

### Architecture

Application **Elixir umbrella** avec 4 apps :
- **balados_sync_core** : Domain, CQRS, Event Sourcing (Commanded)
- **balados_sync_projections** : Read Models, Projectors (Ecto)
- **balados_sync_web** : REST API, Controllers (Phoenix)
- **balados_sync_jobs** : Background Workers

**👉 Détails** : [docs/technical/ARCHITECTURE.md](docs/technical/ARCHITECTURE.md)

---

## 🚀 Quick Start

### Installation & Setup

```bash
mix deps.get
mix db.create
mix db.init
mix phx.server    # http://localhost:4000
```

**👉 Guide complet** : [docs/technical/DEVELOPMENT.md](docs/technical/DEVELOPMENT.md)

---

## 📚 Documentation

| Document | Contenu |
|----------|---------|
| [**docs/GOALS.md**](docs/GOALS.md) | Objectifs et vision |
| [**docs/FEATURES.md**](docs/FEATURES.md) | Fonctionnalités implémentées |
| [**docs/technical/ARCHITECTURE.md**](docs/technical/ARCHITECTURE.md) | Architecture système |
| [**docs/technical/DEVELOPMENT.md**](docs/technical/DEVELOPMENT.md) | Workflow et commandes |
| [**docs/technical/AUTH_SYSTEM.md**](docs/technical/AUTH_SYSTEM.md) | Autorisation JWT |
| [**docs/technical/CQRS_PATTERNS.md**](docs/technical/CQRS_PATTERNS.md) | Patterns CQRS/ES |
| [**docs/technical/DATABASE_SCHEMA.md**](docs/technical/DATABASE_SCHEMA.md) | Architecture BD |
| [**docs/technical/POST_MERGE_FOLLOWUPS.md**](docs/technical/POST_MERGE_FOLLOWUPS.md) | Issues de suivi post-merge |

---

## 🎯 Principes Clés

### CQRS/Event Sourcing

**Flux** : Command → Aggregate → Event → EventStore → Projectors → Projections

- **Commands** : Intentions (Subscribe, RecordPlay, ...)
- **Events** : Faits immuables (UserSubscribed, PlayRecorded, ...)
- **Aggregates** : Logique métier (User aggregate)
- **Projections** : Read models dénormalisés

**👉 Patterns** : [docs/technical/CQRS_PATTERNS.md](docs/technical/CQRS_PATTERNS.md)

### Event Store = Source de Vérité

- ❌ **NE JAMAIS** modifier manuellement la DB `events`
- ✅ Events sont **immuables** (émettre nouvel event pour "supprimer")
- ⚠️ **Exception** : Les deletion events supprimaient l'historique (disparaissent après 45j)

### Projections = Eventual Consistency

- Délai normal : quelques millisecondes
- Pour reset : `mix db.reset --projections` (SAFE, replay automatique)

---

## 🔐 Autorisation

OAuth-style JWT flow avec scopes hiérarchiques :

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

**👉 Détails** : [docs/technical/AUTH_SYSTEM.md](docs/technical/AUTH_SYSTEM.md)

---

## 🗄️ Base de Données

### Trois Repos Ecto

| Repo | Schema | Type | Commande |
|------|--------|------|----------|
| **SystemRepo** | `system` | Permanent (users, tokens) | `mix system.migrate` |
| **ProjectionsRepo** | `public` | Event-sourcées (read models) | `mix projections.migrate` |
| **EventStore** | `events` | Immuable (source de vérité) | Automatique (Commanded) |

### Commandes

```bash
mix db.migrate              # Tous les repos
mix system.migrate          # Seulement system
mix projections.migrate     # Seulement projections
mix db.reset --projections  # ✅ SAFE - reset projections
mix db.reset --all          # ☢️  DANGER - tout détruit
```

**⚠️** Ne pas utiliser `mix ecto.*` directement

**👉 Détails** : [docs/technical/DATABASE_SCHEMA.md](docs/technical/DATABASE_SCHEMA.md)

---

## 🧪 Tests

```bash
mix test                    # Tous les tests
mix test --cover           # Avec couverture
cd apps/balados_sync_core && mix test  # App spécifique
```

---

## 🔄 Background Workers & Cleanup Tasks

### PlayToken Expiration Cleanup

PlayTokens are automatically expired based on configuration (default: 365 days). Expired tokens are periodically cleaned up to maintain database performance.

**Manual Cleanup** (if needed in production):
```bash
# Execute cleanup worker manually
mix run -e "BaladosSyncJobs.PlayTokenCleanupWorker.perform()"

# Or from iex
iex> BaladosSyncJobs.PlayTokenCleanupWorker.perform()
```

**Configuration**:
```elixir
# config/config.exs
config :balados_sync_projections,
  play_token_expiration_days: 365  # Default: 1 year

config :balados_sync_jobs,
  play_token_cleanup_batch_size: 1000  # Optional: batch deletion size
```

**Monitoring**:
- Monitor token accumulation: Check `system.play_tokens` table for expired tokens
- Set up alerts if expired tokens are not being cleaned up
- Backup database before first cleanup run in production

**Important Notes**:
- Cleanup is safe: only removes expired and revoked tokens
- Partial index on `expires_at` optimizes cleanup queries
- Cleanup respects transaction boundaries (atomic deletions)

---

## 📝 Notes pour Claude Code

### Prérequis

- Tu ne peux pas démarrer/arrêter le serveur Phoenix
- Mets à jour docs/ après chaque commit
- Consulte les docs thématiques plutôt que de tout garder dans CLAUDE.md

### Workflow de Développement

**⚠️ IMPORTANT**: Le workflow de développement complet est défini dans [.claude/agents/development-workflow.md](.claude/agents/development-workflow.md). Ce fichier doit être suivi à la lettre pour toute tâche de développement.

### Task Queue (TODOS.md)

Le fichier [TODOS.md](TODOS.md) sert de file d'attente pour les tâches :
- **TODO** : Tâches ajoutées par les humains
- **In Progress** : Tâches avec issue/PR associée (maintenu par Claude)
- **Done** : Tâches terminées

Lors du workflow, toujours vérifier TODOS.md pour :
1. Synchroniser les tâches avec GitHub (issues/PRs)
2. Créer des issues pour les nouvelles tâches
3. Mettre à jour les statuts

### Résumé du Workflow (Issue → PR)

#### Phase 1: Analyser l'Issue
```bash
# Récupérer issues ouvertes
gh issue list --state open --json number,title,labels,createdAt

# Afficher détails d'une issue
gh issue view <number>

# Prioriser par: labels (phase-N, priority), age, réactions
```

#### Phase 2: Créer une Branche Feature
```bash
git checkout main
git pull origin main
git checkout -b feature/issue-<number>-<slugified-title>

# Exemple: feature/issue-9-add-playtoken-expiration
```

#### Phase 3: Implémenter avec Tests
- Respecter CQRS/ES : [docs/technical/CQRS_PATTERNS.md](docs/technical/CQRS_PATTERNS.md)
- Events immuables : toujours émettre nouveaux events
- Ajouter tests pour nouveaux commands/events/projectors
- Mettre à jour docs/ si changements d'architecture
- Tester localement: `mix test`
- Appliquer migrations: `mix db.migrate`

#### Phase 4: Committer
```bash
# Vérifier changements
git diff main
git status

# Committer avec auteur Claude
git add -A
git commit --author="Claude <noreply@anthropic.com>" -m "feat: description

- Changement 1
- Changement 2

Closes #<issue-number>"
```

#### Phase 5: Créer la PR
```bash
# Pousser branche
git push -u origin feature/issue-<number>-<title-slug>

# Créer PR
gh pr create --title "feat: description (Closes #<number>)" \
  --body "## Summary

Brief description

## Test Plan
- Test 1
- Test 2"
```

#### Phase 6: Post-Merge Follow-up (si PR mergee avec comments)
```bash
# Verifier si la PR a des follow-ups necessaires
gh pr view <number> --comments

# Criteres pour creer des issues de suivi:
# - MUST-FIX: tests manquants, logging absent, docs non a jour
# - SHOULD-FIX: error handling incomplet, TODOs dans le code
# - NICE-TO-HAVE: optimisations, refactoring suggere

# Creer les issues de suivi
gh issue create \
  --title "[Follow-up #<PR>] <description>" \
  --label "follow-up,from-pr-<PR>,<priority-label>" \
  --body "## Context
Follow-up from PR #<PR>: <title>

## Original Finding
> <quote du commentaire>

## Acceptance Criteria
- [ ] Critere 1
- [ ] Critere 2
- [ ] Tests ajoutes"
```

#### Phase 7: Boucler sur Main
```bash
# Retourner a main
git checkout main
git pull origin main

# Boucler: revenir a Phase 1 (issues/PRs)
```

### Post-Merge Follow-up Issues

**Quand creer des issues de suivi:**
| Categorie | Labels | Exemples |
|-----------|--------|----------|
| **must-fix** | `priority-critical` | Tests manquants, logging absent, security |
| **should-fix** | `priority-high` | Error handling, validation, TODOs |
| **nice-to-have** | `enhancement` | Optimisations, refactoring, UX |

**Labels obligatoires:** `follow-up`, `from-pr-<N>`

**Triggers automatiques:**
- Commentaires avec "TODO", "FIXME", "later", "follow-up"
- Tests coverage < 80% sur nouveau code
- Threads non resolus dans la review
- PR mergee avec "approved with comments"

**Format titre:** `[Follow-up #<PR>] <type>: <description>`

**⚠️ RÈGLE IMPORTANTE: Pas de follow-up de follow-up !**
- Si tu travailles sur une issue de suivi (follow-up), tu dois la résoudre complètement
- Ne jamais créer une issue de suivi pour une issue qui est déjà un follow-up
- Si le problème est trop complexe, demander de l'aide ou simplifier l'approche
- Les issues de suivi doivent être terminées, pas reportées

### Points Importants

**Git & Commits:**
- Auteur: `--author="Claude <noreply@anthropic.com>"`
- Messages: commits atomiques, clairs, format conventionnel
- Branches: `feature/issue-<number>-<slug>` (pas de long noms)
- PR: créer toujours une PR (validation + traçabilité)
- **⚠️ MERGE OBLIGATOIRE: `gh pr merge --merge --delete-branch` (JAMAIS --squash)**
- **🚫 RÈGLE INVIOLABLE: JAMAIS de `git push --force` sans autorisation explicite de l'utilisateur**

**Tests & Database:**
- Migrations en test: `MIX_ENV=test mix db.migrate`
- Reset test DB: `echo "DELETE ALL DATA" | MIX_ENV=test mix db.reset --all`
- Tous les tests doivent passer avant PR
- DataCase pour tests avec DB (créer si inexistant)

**Code Quality:**
- Pas de modifications "proactives" au-delà de la tâche
- CQRS/ES obligatoire pour les commands/events
- Logging pour audit trail (ex: token expiration)
- Backward compatibility si possible (champs optionnels)

---

## 🎙️ Fonctionnalités Implémentées

**👉 Détails complets** : [docs/FEATURES.md](docs/FEATURES.md)

- Web Subscription Interface (v1.0)
- Play Gateway avec Auto-token (v1.1+)
- Live WebSocket Gateway (v1.2)
- Subscription Pages Refactoring (v1.3)
- Privacy Choice Modal (v1.4)
- Privacy Manager Page (v1.5)
- PlayToken Expiration & Auto-cleanup (v1.6) ✅ [#30](https://github.com/podCloud/balados.sync/pull/30)
- Public Timeline Page with Activity Feed (v1.7) ✅ [#40](https://github.com/podCloud/balados.sync/pull/40)
- Collections & Organization (v1.8) ✅ [#45](https://github.com/podCloud/balados.sync/pull/45)
- RSS Aggregate Feeds (v1.9) ✅ [#64](https://github.com/podCloud/balados.sync/issues/64)
- Playlists CRUD Web UI (v2.0) ✅ [#28](https://github.com/podCloud/balados.sync/issues/28)
- Enriched Podcasts (v2.1) ✅ [#65](https://github.com/podCloud/balados.sync/issues/65)
- Public User Profiles (v2.2) ✅ [#66](https://github.com/podCloud/balados.sync/issues/66)
- Public Visibility for Playlists/Collections (v2.3) ✅ [#67](https://github.com/podCloud/balados.sync/issues/67)

---

## 📖 Ressources

- [Elixir](https://elixir-lang.org/docs.html)
- [Phoenix](https://hexdocs.pm/phoenix/)
- [Commanded](https://hexdocs.pm/commanded/)
- [EventStore](https://hexdocs.pm/eventstore/)
