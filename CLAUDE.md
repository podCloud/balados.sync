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

### Workflow

1. **Respecter CQRS/ES** : [docs/technical/CQRS_PATTERNS.md](docs/technical/CQRS_PATTERNS.md)
2. **Events immuables** : toujours émettre nouveaux events
3. **Tests** : ajouter tests pour nouveaux commands/events/projectors
4. **Documentation** : mettre à jour docs/ si changements d'architecture

---

## 🎙️ Fonctionnalités Implémentées

**👉 Détails complets** : [docs/FEATURES.md](docs/FEATURES.md)

- Web Subscription Interface (v1.0)
- Play Gateway avec Auto-token (v1.1+)
- Live WebSocket Gateway (v1.2)
- Subscription Pages Refactoring (v1.3)
- Privacy Choice Modal (v1.4)
- Privacy Manager Page (v1.5)

---

## 📖 Ressources

- [Elixir](https://elixir-lang.org/docs.html)
- [Phoenix](https://hexdocs.pm/phoenix/)
- [Commanded](https://hexdocs.pm/commanded/)
- [EventStore](https://hexdocs.pm/eventstore/)
