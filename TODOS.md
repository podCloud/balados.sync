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

## In Progress

Format: `- [ ] Description - [#N](url) - STATUS`

- [ ] Enriched podcasts with slugs, branding, social links - [#65](https://github.com/podCloud/balados.sync/issues/65) - OPEN
- [ ] Public user profile page - [#66](https://github.com/podCloud/balados.sync/issues/66) - OPEN
- [ ] Public visibility for playlists and collections - [#67](https://github.com/podCloud/balados.sync/issues/67) - OPEN
- [ ] Podcast ownership via RSS verification code - [#68](https://github.com/podCloud/balados.sync/issues/68) - OPEN
- [ ] Email verification for podcast ownership - [#69](https://github.com/podCloud/balados.sync/issues/69) - OPEN

---

## Done

Format: `- [x] Description - [#N](url)`

- [x] Timeline actions 3-dot menu - [#22](https://github.com/podCloud/balados.sync/issues/22) - PR #90
- [x] Toast notifications accessibility - [#52](https://github.com/podCloud/balados.sync/issues/52) - PR #93
- [x] Collections: reorder feeds - [#51](https://github.com/podCloud/balados.sync/issues/51) - PR #95
- [x] Playlists UI and CRUD - [#28](https://github.com/podCloud/balados.sync/issues/28) - PR #91
- [x] Persist timeline filter preferences - [#53](https://github.com/podCloud/balados.sync/issues/53) - PR #92
- [x] RSS aggregate feeds for collections/playlists - [#64](https://github.com/podCloud/balados.sync/issues/64) - PR #84
