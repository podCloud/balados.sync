# Workflow stack — balados.sync (Elixir/Phoenix CQRS-ES)

## Commands
- Test: `mix test`  | Format: `mix format`
- Migrations: `mix db.migrate` ET `MIX_ENV=test mix db.migrate` (avant tests)
- `gh` : toujours via `~/.config/podclaude/gh.sh`

## Conventions
- CQRS/ES : Command → Aggregate → Event → Projector → Projection. Events immuables.
- 5 bounded contexts (Subscription, PlayTracking, Playlist, Collection, Like).
- Repos Ecto : SystemRepo / ProjectionsRepo / EventStore. Ne jamais `mix ecto.*` directement.
- Référence : docs/technical/CQRS_PATTERNS.md.
- Branches: `feature/issue-<n>-<slug>`. Auteur: Claude <noreply@anthropic.com>.

## TODOS.md
- Au DISCOVER : synchroniser TODOS.md ↔ GitHub (issues/PR), mettre à jour les statuts.

## PR
- Créer la PR via `~/.config/podclaude/gh.sh pr create …` sans label de review automatique.

## Tests qui échouent
- Ne jamais ignorer un test en échec : créer une issue GitHub pour le tracker.
