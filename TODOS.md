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

- [ ] Ajouter la possibilité de charger des agrégats RSS des collections d'abonnements ou bien des playlists en utilisant RSS proxy pour récupérer tous les flux et créer le nouveau. Les agrégats RSS ont besoin du play_token dans l'URL pour fonctionner. Utiliser plutôt une partie de l'url qu'un paramètre get.
- [ ] Ajouter la possibilité pour les admins d'ajouter une liste de flux "enrichis" enriched_podcasts, dans lequel on peut choisir un alias slug qui s'affichera dans la barre d'adresse, la couleur de fond de la page du podcast et ajouter une liste de liens qui pourront être soir un lien personnalisé soit choisir dans la liste un réseau social pour en afficher les icônes.

  Un admin peut depuis une page de flux ou en rentrant un flux RSS dans une page de l'admin accéder à la gestion de l'émission sur l'admin. Cette page affichera les dernières stats scopé au podcast lui même, et permettra de modifier des infos, comme présenté ci dessus.

  Un utilisateur lambda pourra donc accéder au flux en utilisant son alias slug au lieu du base 64. Il faudra le prendre en compte dans le controller

- [ ] Ajouter une page publique de profil utilisateur. Ajouter dans les paramètres de profil de l'utilisateur la possibilité de désactiver le profil public. Afficher la timeline publique de l'utilisateur. Ajouter la notion de nom public, ajouter la possibilité de changer son avatar.
- [ ] Ajouter la possibilité de rendre public ses playlists et ses collections. Préciser qu'elles seront visibles sur le profil public d'utilisateur. Et pourront être accédés avec un lien
- [ ] Ajouter la possibilité pour les utilisateur de récupérer l'administration d'un podcast pour gérer ses enriched metadata. Plusieurs utilisateurs peuvent avoir l'admin donc utiliser un tableau de user id dans la table enriched podcasts. Pour cela il doit inclure un code à l'intérieur du flux de podcast qui sera vérifié sans cache et raw pour voir si le code est trouvé quelque part dans la source.
- [ ] Dans un deuxième temps on peut aussi choisir d'envoyer un code de vérification dans l'autre sens par email à un email présent dans le podcast. Quand l'utilisateur ajoute l'émission à son compte il peut le faire de façon privée ou publique. Si c'est privé ça reste uniquement dans son interface. Si c'est public ça s'affiche dans son profil public.

---

## In Progress

Format: `- [ ] Description - [#N](url) - STATUS`

---

## Done

Format: `- [x] Description - [#N](url)`
