# Workflow stack — balados.sync (Elixir umbrella / Phoenix 1.8 / LiveView 1.2 / CQRS-ES)

## Commands
- Install (worktree) : `mix deps.get`, puis `MIX_ENV=test mix db.create && MIX_ENV=test mix db.init` sur une base vierge (sinon `MIX_ENV=test mix db.migrate`) avant les tests.
- Test : `mix test --exclude e2e` (suite rapide, ~940 tests ; les tests navigateur sont déjà exclus par défaut) | navigateur : `mix test --include e2e` quand le rendu change (ChromeDriver requis).
- Compile : `mix compile --warnings-as-errors`
- Format : `mix format --check-formatted` depuis la racine de l'umbrella (voir piège ci-dessous).
- Migrations : `mix db.migrate` ET `MIX_ENV=test mix db.migrate`. Ne jamais `mix ecto.*` directement.
- `gh` : toujours via `~/.config/podclaude/gh.sh`

## Conventions
- CQRS/ES : Command → Aggregate → Event → Projector → Projection. Events immuables.
- 5 bounded contexts (Subscription, PlayTracking, Playlist, Collection, Like).
- Repos Ecto : SystemRepo / ProjectionsRepo / EventStore.
- Auth : `BaladosSyncWeb.Plugs.JWTAuth` (`scopes` / `scopes_any`, 401 sans token, 403 scope insuffisant) ; tests avec `JwtTestHelper.authenticate_conn/3`.
- Rate limit : `BaladosSyncWeb.Plugs.RateLimiter` sur `BaladosSyncWeb.RateLimit` (Hammer 7, table ETS globale, `{:deny, retry_after_ms}`) ; en test, `BaladosSyncWeb.RateLimit.reset/0` seulement dans un module `async: false`, sinon un `user_id` distinct par test.
- Cache RSS : Cachex `:rss_feed_cache`, 5 min ; en test, `on_exit` avec `Cachex.del`.
- Référence : docs/technical/CQRS_PATTERNS.md, docs/technical/AUTH_SYSTEM.md.
- Branches : `feature/issue-<n>-<slug>`. Worktrees dans `.worktrees/` (gitignoré). Auteur : Claude <noreply@anthropic.com>.
- Doc avec le code : `docs/FEATURES.md`, `docs/technical/*.md`, `README.md`, `TODOS.md`, `CLAUDE.md`, gettext fr/en.

## Pièges connus
- Hook pre-commit (`.githooks/`) : lance `mix format <fichiers>` depuis la racine, sans le `locals_without_parens` de Phoenix, et réécrit `plug X` en `plug(X)` (#272). Tant que ce n'est pas corrigé : vérifier `git diff <base> -- <fichier>` juste avant chaque commit touchant `endpoint.ex` / `router.ex` / des plugs de controller ; si le hook réintroduit des parenthèses, `mix format --check-formatted` à la main puis `git commit --no-verify`.
- HEEx (LiveView 1.x) : une accolade littérale dans le texte d'un gabarit est une expression ; mettre `phx-no-curly-interpolation` sur l'élément. Un `<form phx-change>` sans `id` déclenche un avertissement en test. `Phoenix.LiveViewTest` repose sur `lazy_html` (plus de Floki). Le formateur HEEx change d'une version de LiveView à l'autre : relancer `mix format` après une montée.
- `mix gettext.extract --check-up-to-date` échoue sur main (#269) : ne pas l'ajouter au gate tant que ce n'est pas corrigé.
- Tests flaky connus : `MessageHandlerTest` PLAY_RATE_LIMITED (#266) ; `LiveWebSocket.RateLimiterTest` bucket vide (#274) ; LiveView historiques (#246).
- CI : workflow `Tests` (job `Compile, format and test`) sur chaque PR ; vérifier `~/.config/podclaude/gh.sh pr checks <n>` avant de merger.

## TODOS.md
- Au DISCOVER : synchroniser TODOS.md ↔ GitHub (issues/PR), mettre à jour les statuts.

## PR
- Créer la PR via `~/.config/podclaude/gh.sh pr create …` sans label de review automatique.
- Changement de contrat API (auth, codes, encodage) : marquer ⚠️ Breaking dans le README et `docs/FEATURES.md`.

## Tests qui échouent
- Ne jamais ignorer un test en échec : créer une issue GitHub pour le tracker.
