# Objectifs et Vision - Balados Sync

## 🎯 Objectif Principal

**Balados Sync est un serveur backend de synchronisation de podcasts** - il stocke les abonnements, positions d'écoute, playlists et métadonnées, et expose une API pour synchroniser ces données entre différents appareils et applications.

### Ce que Balados Sync EST

- **Un serveur de stockage et synchronisation** : API REST/WebSocket pour sync bidirectionnelle
- **Des pages web de gestion basiques** : Interface CRUD pour consulter/gérer ses données (abonnements, playlists, collections, timeline)
- **Un générateur de flux RSS** : Export des playlists/collections en flux RSS agrégés
- **Une plateforme de découverte** : Timeline publique, popularité, profils utilisateurs

### Ce que Balados Sync N'EST PAS

- **Pas un lecteur de podcast** : Aucune fonctionnalité de lecture audio
- **Pas une app mobile/desktop** : Backend only, pas d'interface native
- **Pas une solution offline** : Stockage serveur, pas local

### Relation avec Balados App

**Balados App** (`balados.app`) est un projet frontend séparé qui sera :
- Un lecteur de podcast complet avec support offline
- Une application autonome (fonctionne sans compte Sync)
- Capable de se synchroniser **optionnellement** avec Balados Sync

```
┌─────────────────┐         ┌─────────────────┐
│  Balados Sync   │◄──API──►│  Balados App    │
│  (Backend)      │         │  (Frontend)     │
│                 │         │                 │
│ • Stockage      │         │ • Lecteur       │
│ • Sync API      │         │ • Offline       │
│ • Pages CRUD    │         │ • UI native     │
│ • RSS exports   │         │ • Synchro opt.  │
└─────────────────┘         └─────────────────┘
        ▲
        │ API
        ▼
┌─────────────────┐
│  Apps tierces   │
│  (AntennaPod,   │
│   Pocket Casts) │
└─────────────────┘
```

## 👥 Public Cible

Balados Sync s'adresse à plusieurs types d'utilisateurs :

- **Utilisateurs finaux grand public** : Personnes écoutant des podcasts qui veulent synchroniser leur expérience entre appareils
- **Développeurs d'applications de podcasts** : Intégration de la synchronisation dans des apps tierces via API
- **Communauté self-hosted** : Possibilité pour chacun de déployer son propre serveur
- **Usage personnel** : Le projet sert aussi mes propres besoins de synchronisation

## 🚀 Priorités Actuelles

### Stabilité et Fiabilité

L'accent est mis sur la **stabilité et la fiabilité du système existant** :
- Corriger les bugs identifiés
- Améliorer la robustesse du système CQRS/Event Sourcing
- Assurer la cohérence des données entre le Event Store et les projections
- Tester les cas limites et les scénarios de récupération d'erreurs

## 🎨 Fonctionnalités Clés (Stockage & Sync)

### 1. Synchronisation des Positions d'Écoute ✅
- **Stockage** des positions d'écoute par épisode
- **API** pour mise à jour temps réel (WebSocket)
- **Résolution de conflits** multi-appareils (last-write-wins)

### 2. Gestion des Abonnements ✅
- **Stockage** des abonnements podcast (feed URLs)
- **Sync bidirectionnelle** via API
- **Métadonnées enrichies** (titre, artwork, ownership)

### 3. Playlists et Collections ✅
- **Stockage** de playlists personnalisées et collections
- **Export RSS** des playlists/collections (flux agrégés)
- **Visibilité publique/privée** configurable

### 4. Découverte et Social ✅
- **Timeline publique** des écoutes de la communauté
- **Profils utilisateurs** publics
- **Popularité** basée sur les données agrégées

### 5. Pages Web de Gestion ✅
- Interface CRUD pour gérer ses données stockées
- Consultation des abonnements, playlists, timeline
- **Pas de lecteur audio** - juste consultation/gestion

## 🔒 Vie Privée

La vie privée est **importante** avec un **contrôle granulaire par l'utilisateur** :

### Système à 3 Niveaux
- **Public** : Visible avec user_id (pour partage avec la communauté)
- **Anonymous** : Visible sans user_id (statistiques anonymes)
- **Private** : Complètement caché

### Contrôle Granulaire
- Configuration globale par utilisateur
- Override par podcast (feed)
- Override par épisode individuel
- Mise à jour dynamique des données publiques

## 💻 Contexte Technique

### Niveau d'Expérience
**Intermédiaire** en Elixir et CQRS/ES - j'utilise ces technologies et apprends en pratiquant. Ce projet est une excellente opportunité d'approfondir ces compétences.

### Défis Techniques Identifiés

#### 1. Performance du Parsing RSS
- Optimiser le fetching concurrent de feeds
- Mise en cache intelligente
- Parsing efficace de XML volumineux
- Gestion des timeouts et erreurs réseau

#### 2. Scalabilité
- Architecture capable de gérer des milliers d'utilisateurs
- Optimisation des projections et requêtes
- Event Store performant sur le long terme
- Workers asynchrones efficaces

## 📅 Évolution sur 6 Mois

### Objectifs Court Terme (1-6 mois)

#### 1. Lancement d'un MVP Public
- Version beta accessible à des utilisateurs externes
- API stable et documentée
- Interface web basique de gestion
- Monitoring et métriques

#### 2. Intégrations avec Apps Existantes
- Développer des SDKs/libraries pour faciliter l'intégration
- Partenariats avec développeurs d'apps de podcasts
- Documentation complète pour développeurs
- Exemples d'intégration

#### 3. Consolidation Technique et Tests
- Suite de tests complète (unit, integration, e2e)
- Amélioration de la couverture de tests
- Optimisations de performance
- Documentation technique exhaustive
- CI/CD robuste

## 🔮 Vision à Long Terme

### Double Objectif : Ouverture et Fédération

#### Standard Ouvert de Synchronisation
- Devenir une référence pour la sync inter-apps de podcasts
- Protocole ouvert que d'autres peuvent implémenter
- Compatibilité entre différentes instances

#### Infrastructure Self-Hostable
- Déploiement facile pour chacun
- Documentation complète d'installation
- Configuration simplifiée
- Support multi-instance

#### Plateforme de Découverte Communautaire
- Partage des écoutes sur chaque instance
- Statistiques de popularité par communauté
- Découverte locale (par instance) et globale (fédérée)
- Respect de la vie privée dans le partage

### Modèle Hybride

Le projet vise un modèle **hybride** :
- **Fédération** : Chaque instance est autonome mais peut échanger
- **Open Source** : Code ouvert, contributions bienvenues
- **Communautaire** : Chaque instance a sa propre communauté
- **Découverte Locale** : Recommandations basées sur l'instance
- **Standard Ouvert** : Protocole interopérable entre instances

## 📊 Statut de Production

**Production future après validation** :
- Actuellement en développement actif
- Tests et validation nécessaires avant lancement public
- Infrastructure de production à planifier
- Monitoring et observabilité à mettre en place

### Prochaines Étapes Vers Production

1. **Phase de Stabilisation** (actuel)
   - Corriger bugs identifiés
   - Tests approfondis
   - Documentation complète

2. **Phase Beta Privée**
   - Déploiement sur serveur de prod
   - Invitation d'utilisateurs beta testeurs
   - Collecte de feedback
   - Amélioration continue

3. **Phase Beta Publique**
   - Ouverture au public avec disclaimer beta
   - Monitoring en temps réel
   - Support communautaire
   - Documentation utilisateur

4. **Production Stable**
   - Version 1.0 stable
   - SLA et garanties de service
   - Support multiple instances
   - Fédération entre instances

## 🎓 Apprentissage et Expérimentation

Le projet sert aussi de terrain d'apprentissage pour :
- **CQRS/Event Sourcing** en conditions réelles
- **Elixir/Phoenix** à grande échelle
- **Architecture distribuée** et patterns de scalabilité
- **Event Store** et gestion d'événements immuables
- **API Design** pour développeurs tiers

## 🤝 Contribution et Communauté

### Ouverture aux Contributions
- Code open source (prévu)
- Issues et pull requests bienvenues
- Documentation pour contributeurs
- Guidelines de contribution

### Construction de Communauté
- Forum ou Discord pour discussions
- Partage d'expériences entre instances
- Collaboration sur le protocole standard
- Événements communautaires

## 📝 Notes Importantes

- **Pas de monétisation prévue** : Le projet reste open source et communautaire
- **Respect des standards RSS/Atom** : Compatibilité maximale
- **Pas de lock-in** : Export facile des données
- **API First** : Tout passe par l'API, web UI est secondaire
- **Événements immuables** : Audit trail complet de toutes les actions

---

**Dernière mise à jour** : 2026-01-09
**Statut** : 🟢 En développement actif - Backend sync server, core features complete
