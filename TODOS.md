# Task Queue

Sync tasks between this file and GitHub issues/PRs.

## Workflow

1. **Sync**: Fetch open issues and PRs from GitHub
2. **Process TODO**: For each task below, find or create a GitHub issue
3. **Update statuses**: Refresh In Progress section with current state
4. **Commit**: Push changes to TODOS.md

## Issue Template

When creating issues, use this prompt-optimized format:

```
## Objective
<what needs to be done>

## Context
<why it matters, relevant files>

## Implementation
1. Step 1
2. Step 2

## Acceptance Criteria
- [ ] Criterion 1
- [ ] Tests pass
```

## Status Codes

| Status | Meaning |
|--------|---------|
| `OPEN` | Issue created |
| `WIP` | PR in development |
| `REVIEW` | PR awaiting review |
| `MERGED` | Done |

---

## TODO

- [ ] Example task description here


---

## In Progress

<!-- Format: - [ ] Description - [#N](url) - STATUS -->


---

## Done

