---
description: Manage PRs, issues, and automate development workflow
argument-hint: [optional: issue number to focus on]
---

# Continuous Development Workflow

Automated workflow to manage pull requests, issues, and development cycles.

## Instructions

### Phase 1: Audit Existing Pull Requests

1. **Fetch all open PRs** using:
   ```bash
   gh pr list --state open --json number,title,reviews,reviewDecision --limit 50
   ```

2. **For each PR with pending reviews or requested changes**:
   - Checkout the PR branch: `git fetch origin && git checkout <branch>`
   - Read and analyze the review comments using `gh pr view <number> --comments`
   - Identify all actionable feedback
   - Make necessary corrections following the review comments
   - Commit changes with descriptive messages
   - Push back to the branch: `git push origin <branch>`
   - Post a comment on the PR acknowledging the changes: `gh pr comment <number> --body "Changes implemented per review feedback"`

3. **If all feedback is addressed**:
   - Mark PR as ready: `gh pr comment <number> --body "Ready for review"`
   - Return to main branch: `git checkout main && git pull origin main`

---

### Phase 2: Assess Open Issues

1. **Fetch all open issues** that are NOT assigned:
   ```bash
   gh issue list --state open --assignee none --json number,title,labels,reactions --limit 50
   ```

2. **Prioritize by**:
   - Labels (check for `priority:high`, `priority:critical`, `bug`)
   - Reaction count (👍 indicates community interest)
   - Age (older issues first, unless explicitly marked otherwise)

3. **If an issue number was provided as $ARGUMENTS**:
   - Focus on that specific issue
   - Skip the prioritization step and jump directly to it

4. **Select the highest priority issue** and continue to Phase 3

---

### Phase 3: Start Development Work

1. **Mark the issue as "in progress"**:
   ```bash
   gh issue edit <issue-number> --state open
   gh issue comment <issue-number> --body "Starting work on this issue"
   ```

2. **Create a feature branch**:
   - Extract issue title and number
   - Format: `feature/issue-<number>-<slugified-title>`
   - Example: `feature/issue-42-add-dark-mode`
   ```bash
   git checkout main
   git pull origin main
   git checkout -b feature/issue-<number>-<title-slug>
   ```

3. **Implement the solution**:
   - Read all relevant code documentation first
   - Follow the CQRS/Event Sourcing patterns from docs/technical/CQRS_PATTERNS.md
   - Add appropriate tests
   - Update documentation if architecture changes
   - Commit regularly with clear messages:
     ```bash
     git commit -m "feat: description of changes

     - Specific change 1
     - Specific change 2

     Closes #<issue-number>"
     ```

4. **Verify everything works**:
   - Run tests: `mix test`
   - Check formatting: `mix format`
   - Review changes: `git diff main`

---

### Phase 4: Create and Submit Pull Request

1. **Push the feature branch**:
   ```bash
   git push origin feature/issue-<number>-<title-slug>
   ```

2. **Create a pull request**:
   ```bash
   gh pr create \
     --title "feat: <clear description> (Closes #<issue-number>)" \
     --body "## Summary

   Brief description of changes

   ## Related Issue
   Closes #<issue-number>

   ## Test Plan
   - Step 1 to test
   - Step 2 to test

   ## Checklist
   - [x] Tests added/updated
   - [x] Documentation updated
   - [x] CQRS patterns followed"
   ```

3. **Link PR to issue**:
   ```bash
   gh issue comment <issue-number> --body "PR created: #<pr-number>"
   ```

---

### Phase 5: Update Issue Status

1. **Mark issue as "pending review"**:
   ```bash
   gh issue comment <issue-number> --body "✅ Implementation complete, PR #<pr-number> submitted for review"
   ```

2. **Add label** (if not already present):
   ```bash
   gh issue edit <issue-number> --add-label "status:in-review"
   ```

---

### Phase 6: Return to Main and Loop

1. **Cleanup**:
   ```bash
   git checkout main
   git pull origin main
   ```

2. **Check for new PRs with feedback** (go back to Phase 1)

3. **If no PRs need fixing, pick next issue** (go back to Phase 2)

---

## Usage Examples

```bash
# Run continuous workflow (auto-selects highest priority issue)
/continue-todos

# Focus on a specific issue
/continue-todos 42

# Run once to handle PRs only
/continue-todos --pr-only

# Run once to handle a single issue
/continue-todos --single-issue
```

---

## Workflow Diagram

```
┌─────────────────────────────────────┐
│  Phase 1: Audit PRs                 │
│  - Fetch open PRs                   │
│  - Fix review feedback              │
│  - Push corrections                 │
└────────────┬────────────────────────┘
             │
             ▼
┌─────────────────────────────────────┐
│  Phase 2: Assess Issues             │
│  - Find open unassigned issues      │
│  - Prioritize                       │
│  - Select highest priority          │
└────────────┬────────────────────────┘
             │
             ▼
┌─────────────────────────────────────┐
│  Phase 3: Implement                 │
│  - Create feature branch            │
│  - Code solution                    │
│  - Test & format                    │
└────────────┬────────────────────────┘
             │
             ▼
┌─────────────────────────────────────┐
│  Phase 4: Create PR                 │
│  - Push branch                      │
│  - Create PR with description       │
│  - Link to issue                    │
└────────────┬────────────────────────┘
             │
             ▼
┌─────────────────────────────────────┐
│  Phase 5: Update Issue              │
│  - Mark as in-review                │
│  - Add status label                 │
└────────────┬────────────────────────┘
             │
             ▼
┌─────────────────────────────────────┐
│  Phase 6: Loop                      │
│  - Return to main                   │
│  - Go back to Phase 1 or 2          │
└─────────────────────────────────────┘
```

---

## Key Principles

- **Continuous Loop**: Handles PRs, then issues, then repeats
- **CQRS Adherence**: Follow Event Sourcing patterns from documentation
- **Atomic Commits**: Each commit is meaningful and relates to issue
- **Clear Communication**: Update GitHub with progress
- **Testing First**: Ensure all tests pass before PR
- **Documentation**: Update docs/ if architecture changes

---

## Integration with Claude Code

This command uses:
- `gh` CLI for GitHub operations
- Standard git commands
- `mix` commands for testing
- Read tool for documentation review
- Edit/Write tools for code changes
- TodoWrite tool to track progress

The workflow respects the CQRS/Event Sourcing architecture defined in `docs/technical/CQRS_PATTERNS.md`
