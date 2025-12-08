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

## 📝 Notes pour Claude Code

### Prérequis

- Tu ne peux pas démarrer/arrêter le serveur Phoenix
- Mets à jour docs/ après chaque commit
- Consulte les docs thématiques plutôt que de tout garder dans CLAUDE.md

### Workflow de Développement (Issue → PR)

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

#### Phase 6: Boucler sur Main
```bash
# Retourner à main
git checkout main
git pull origin main

# Boucler: revenir à Phase 1 (issues/PRs)
```

### Points Importants

**Git & Commits:**
- Auteur: `--author="Claude <noreply@anthropic.com>"`
- Messages: commits atomiques, clairs, format conventionnel
- Branches: `feature/issue-<number>-<slug>` (pas de long noms)
- PR: créer toujours une PR (validation + traçabilité)

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

---

## 📖 Ressources

- [Elixir](https://elixir-lang.org/docs.html)
- [Phoenix](https://hexdocs.pm/phoenix/)
- [Commanded](https://hexdocs.pm/commanded/)
- [EventStore](https://hexdocs.pm/eventstore/)
