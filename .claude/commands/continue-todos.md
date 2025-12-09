---
description: Manage PRs, issues, and automate development workflow
argument-hint: "[optional: issue number to focus on] [optional: --flags]"
---

# Continuous Development Workflow

Automated workflow to manage pull requests, issues, and development cycles with full CQRS/Event Sourcing integration.

## Overview

This command automates the complete development cycle:
1. **Phase 0**: Pre-flight checks and safety verification
2. **Phase 1**: Merge approved PRs with `--no-ff` (merge commits)
3. **Phase 2**: Audit and fix PRs with review feedback
4. **Phase 3**: Assess and prioritize open issues
5. **Phase 4**: Implement solutions following CQRS/ES patterns
6. **Phase 5**: Create and submit pull requests
7. **Phase 6**: Loop or terminate based on completion criteria

---

## Instructions

### Phase 0: Pre-flight Checks

**Purpose**: Verify system state before workflow begins

1. **Verify clean working directory**:
   ```bash
   if [ -n "$(git status --porcelain)" ]; then
     echo "❌ ERROR: Working directory not clean"
     echo "Please commit or stash changes"
     exit 1
   fi
   ```

2. **Ensure on main branch**:
   ```bash
   current_branch=$(git branch --show-current)
   if [ "$current_branch" != "main" ]; then
     echo "⚠️ Not on main branch, switching..."
     git checkout main
     git pull origin main
   fi
   ```

3. **Verify gh CLI authentication**:
   ```bash
   if ! gh auth status >/dev/null 2>&1; then
     echo "❌ ERROR: gh CLI not authenticated"
     echo "Run: gh auth login"
     exit 1
   fi
   ```

4. **Parse command arguments**:
   - `--pr-only`: Only process PRs (merge + audit), skip new issues
   - `--single-issue`: Work on one issue then exit
   - `--auto-merge`: Automatically merge approved PRs without confirmation
   - `--max-cycles N`: Maximum workflow cycles (default: 5)
   - `--dry-run`: Show what would happen without executing
   - `ISSUE_NUMBER`: Focus on specific issue (e.g., `42`)

---

### Phase 1: Merge Ready PRs (with --no-ff)

**Purpose**: Merge approved PRs using merge commits (no fast-forward)

**Why --no-ff?** Preserves merge history, maintains clean feature branch timeline, aligns with GitFlow

1. **Fetch all open PRs with merge status**:
   ```bash
   gh pr list --state open \
     --json number,title,reviewDecision,statusCheckRollup,mergeable,headRefName \
     --limit 50 > /tmp/open_prs.json
   ```

2. **Filter PRs that are APPROVED, MERGEABLE, and CI passed**:
   ```bash
   # Requirements:
   # - reviewDecision == "APPROVED"
   # - mergeable == "MERGEABLE"
   # - statusCheckRollup: all checks SUCCESS or empty
   ```

3. **For each mergeable PR**:
   - **Get branch name**: `gh pr view <number> --json headRefName -q '.headRefName'`
   - **Require confirmation** (unless `--auto-merge` flag):
     ```bash
     echo "Merge PR #<number> with --no-ff? (y/N)"
     read -r confirmation
     [ "$confirmation" != "y" ] && continue
     ```
   - **Merge with --no-ff** (FORCE MERGE COMMIT):
     ```bash
     gh pr merge <number> --merge --no-ff --delete-branch
     ```
   - **Update local main**:
     ```bash
     git checkout main
     git pull origin main
     ```
   - **Delete local branch** (if exists):
     ```bash
     git branch -d <branch_name> 2>/dev/null || true
     ```
   - **Add success comment**:
     ```bash
     gh pr comment <number> --body "🎉 Merged with merge commit (--no-ff)

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude Haiku 4.5 <noreply@anthropic.com>"
     ```

4. **Handle merge failures gracefully**:
   - Label PR as "merge-failed"
   - Post diagnostic comment with possible causes
   - Continue to next PR
   - Do NOT block workflow on merge conflicts

---

### Phase 2: Audit Existing Pull Requests

1. **Fetch all open PRs** with pending reviews:
   ```bash
   gh pr list --state open --json number,title,reviews,reviewDecision --limit 50
   ```

2. **For each PR with pending reviews or requested changes**:
   - Checkout the PR branch: `git fetch origin && git checkout <branch>`
   - Read review comments: `gh pr view <number> --comments`
   - Identify all actionable feedback
   - Make necessary corrections following comments
   - **IMPORTANT: Commit with PROPER FORMAT** (see Phase 4)
   - Push back: `git push origin <branch>`
   - Post acknowledgment comment with Claude Code attribution

3. **If all feedback addressed**:
   - Comment: "Ready for review"
   - Return to main: `git checkout main && git pull origin main`

---

### Phase 3: Assess Open Issues

1. **Fetch all open unassigned issues**:
   ```bash
   gh issue list --state open --assignee none \
     --json number,title,labels,createdAt --limit 50
   ```

2. **Prioritize by**:
   - Labels: `priority:critical` > `priority:high` > `bug` > feature
   - Age: Older issues first (unless marked `priority:urgent`)
   - Severity: Bug fixes before features

3. **If issue number provided via arguments** (`/continue-todos 42`):
   - Focus directly on that issue
   - Skip prioritization and jump to Phase 4

4. **Select highest priority issue** and continue to Phase 4

---

### Phase 4: Implement Solution

1. **Mark issue as "in progress"**:
   ```bash
   gh issue edit <issue-number> --state open
   gh issue comment <issue-number> --body "🚀 Starting implementation"
   ```

2. **Create feature branch**:
   ```bash
   git checkout main
   git pull origin main
   git checkout -b feature/issue-<number>-<slug>
   ```
   Example: `feature/issue-42-add-dark-mode`

3. **Implement the solution**:
   - Read relevant documentation first
   - **MANDATORY**: Follow CQRS/Event Sourcing patterns from `docs/technical/CQRS_PATTERNS.md`
   - Commands → Events → Aggregates → Projectors → Projections
   - Events are immutable (emit new events for corrections)
   - Add appropriate tests for commands, events, projectors

4. **Apply database migrations** (CRITICAL - was missing!):
   ```bash
   # Development database
   mix db.migrate

   # Test database (MUST RUN BEFORE TESTS)
   MIX_ENV=test mix db.migrate

   # Verify migrations
   mix db.migrate --check-pending
   ```

5. **Run tests**:
   ```bash
   # Run all tests
   mix test

   # Or specific app tests
   cd apps/balados_sync_core && mix test
   ```

6. **Format code**:
   ```bash
   mix format
   ```

7. **Review changes**:
   ```bash
   git diff main
   git status
   ```

8. **Commit with PROPER FORMAT**:
   ```bash
   git commit --author="Claude <noreply@anthropic.com>" -m "$(cat <<'EOF'
   feat: clear description of changes

   - Specific change 1
   - Specific change 2
   - Specific change 3

   Implements CQRS/ES patterns from docs/technical/CQRS_PATTERNS.md

   Closes #<issue-number>

   🤖 Generated with [Claude Code](https://claude.com/claude-code)

   Co-Authored-By: Claude Haiku 4.5 <noreply@anthropic.com>
   EOF
   )"
   ```

   **Key Requirements**:
   - Use `--author="Claude <noreply@anthropic.com>"`
   - Use HEREDOC format with `$(cat <<'EOF' ... EOF)`
   - Reference CQRS_PATTERNS.md
   - Include `Closes #<issue-number>`
   - Add Claude Code attribution footer
   - Add Co-Authored-By line

---

### Phase 5: Create and Submit Pull Request

1. **Push the feature branch**:
   ```bash
   git push -u origin feature/issue-<number>-<slug>
   ```

2. **Create pull request with comprehensive template**:
   ```bash
   gh pr create \
     --title "feat: clear description (Closes #<issue-number>)" \
     --body "$(cat <<'EOF'
   ## Summary
   Brief description of changes implemented.

   ### Changes Made
   - Change 1: Description
   - Change 2: Description

   ### CQRS/ES Implementation
   - Follows patterns from `docs/technical/CQRS_PATTERNS.md`
   - Events are immutable
   - Projections updated accordingly
   - [Describe command/event/aggregates/projectors]

   ## Related Issue
   Closes #<issue-number>

   ## Test Plan
   - [x] All existing tests pass
   - [x] New tests added for functionality
   - [x] Test database migrated successfully
   - [x] Manual testing completed

   ## Database Changes
   - [x] No database changes
   - [ ] Added migration for SystemRepo
   - [ ] Added migration for ProjectionsRepo
   - [ ] EventStore changes (immutable, new events only)

   ## Documentation
   - [x] Updated `docs/` if architecture changed
   - [x] Updated `CLAUDE.md` if workflow changed
   - [x] Added comments for complex logic

   ## Checklist
   - [x] Tests added/updated and passing
   - [x] CQRS/ES patterns followed
   - [x] Database migrations applied (dev + test)
   - [x] Code formatted with `mix format`
   - [x] Documentation updated

   🤖 Generated with [Claude Code](https://claude.com/claude-code)

   Co-Authored-By: Claude Haiku 4.5 <noreply@anthropic.com>
   EOF
   )"
   ```

3. **Link PR to issue**:
   ```bash
   gh issue comment <issue-number> --body "📝 PR created: #<pr-number>

   Implementation complete, ready for review

   🤖 Generated with [Claude Code](https://claude.com/claude-code)"
   ```

---

### Phase 6: Loop or Terminate

**Purpose**: Decide whether to continue workflow or exit gracefully

1. **Increment cycle counter**:
   ```bash
   CYCLE_COUNT=$((CYCLE_COUNT + 1))
   ```

2. **Evaluate termination conditions**:

   **Condition 1: Max cycles reached**
   ```bash
   if [ $CYCLE_COUNT -ge $MAX_CYCLES ]; then
     echo "✅ Max cycles ($MAX_CYCLES) reached"
     exit 0
   fi
   ```

   **Condition 2: Single issue mode completed**
   ```bash
   if [ "$SINGLE_ISSUE" = true ] && [ -n "$COMPLETED_ISSUE" ]; then
     echo "✅ Single issue mode: completed #$COMPLETED_ISSUE"
     exit 0
   fi
   ```

   **Condition 3: PR-only mode with no open PRs**
   ```bash
   if [ "$PR_ONLY" = true ] && [ -z "$(gh pr list --state open)" ]; then
     echo "✅ PR-only mode: no more open PRs"
     exit 0
   fi
   ```

   **Condition 4: No work found (2 consecutive cycles)**
   ```bash
   if [ "$WORK_FOUND_THIS_CYCLE" = false ]; then
     NO_WORK_CYCLES=$((NO_WORK_CYCLES + 1))
     if [ $NO_WORK_CYCLES -ge 2 ]; then
       echo "✅ No work found for 2 consecutive cycles"
       exit 0
     fi
   else
     NO_WORK_CYCLES=0
   fi
   ```

3. **Continue or exit**:
   ```bash
   echo "=== Workflow Complete ==="
   echo "Cycles completed: $CYCLE_COUNT"
   echo "PRs merged: $PRS_MERGED"
   echo "PRs updated: $PRS_UPDATED"
   echo "Issues completed: $ISSUES_COMPLETED"
   ```

---

## Error Handling

**Philosophy**: Fail gracefully, never corrupt git state

1. **Pre-flight failures**: Exit immediately (clean state)
2. **Merge failures**: Label PR, comment, continue to next
3. **Test failures**: Comment on issue, don't create PR, move to next issue
4. **Git operation failures**: Rollback branch, return to main, continue
5. **Network failures**: Log error, retry once, skip if still fails

**Error logging**:
```bash
echo "[$(date)] Phase X: error message" >> /tmp/continue_todos_errors.log
```

---

## Usage Examples

```bash
# Full workflow (auto-selects highest priority, max 5 cycles)
/continue-todos

# Focus on specific issue
/continue-todos 42

# Only merge approved PRs
/continue-todos --pr-only

# Auto-merge without confirmation
/continue-todos --pr-only --auto-merge

# Work on one issue then exit
/continue-todos --single-issue

# Run one complete cycle
/continue-todos --max-cycles 1

# Dry run: show what would happen
/continue-todos --dry-run

# Combine flags
/continue-todos 42 --single-issue
/continue-todos --pr-only --auto-merge --max-cycles 1
```

---

## Workflow Diagram

```
┌──────────────────────────────────────┐
│ Phase 0: Pre-flight Checks           │
│ - Verify clean working dir           │
│ - Check main branch                  │
│ - Validate gh CLI auth               │
│ - Parse arguments                    │
└────────────┬─────────────────────────┘
             │
             ▼
┌──────────────────────────────────────┐
│ Phase 1: Merge Ready PRs (--no-ff)   │
│ - Fetch mergeable PRs                │
│ - Merge with merge commits           │
│ - Clean up branches                  │
│ - Handle failures gracefully         │
└────────────┬─────────────────────────┘
             │
             ▼
┌──────────────────────────────────────┐
│ Phase 2: Audit PRs with Feedback     │
│ - Fix review comments                │
│ - Push corrections                   │
│ - Commit with proper format          │
└────────────┬─────────────────────────┘
             │
             ▼
┌──────────────────────────────────────┐
│ Phase 3: Assess Open Issues          │
│ - Fetch and prioritize issues        │
│ - Select highest priority            │
└────────────┬─────────────────────────┘
             │
             ▼
┌──────────────────────────────────────┐
│ Phase 4: Implement Solution          │
│ - CQRS/ES patterns                   │
│ - Migrate test DB (CRITICAL)         │
│ - Run tests                          │
│ - Commit with proper format          │
└────────────┬─────────────────────────┘
             │
             ▼
┌──────────────────────────────────────┐
│ Phase 5: Create Pull Request         │
│ - Push branch with -u flag           │
│ - Create PR with template            │
│ - Link to issue                      │
└────────────┬─────────────────────────┘
             │
             ▼
┌──────────────────────────────────────┐
│ Phase 6: Loop or Terminate           │
│ - Check termination conditions       │
│ - Continue or exit gracefully        │
└──────────────────────────────────────┘
```

---

## Key Principles

- **Complete Cycles**: Each loop processes PRs then issues
- **CQRS Adherence**: Event Sourcing patterns mandatory for commands/events
- **Atomic Commits**: Each commit meaningful and related to issue
- **Proper Attribution**: All commits include Claude Code footer
- **Test Database Migration**: ALWAYS run before tests (was a critical bug)
- **Merge Commits**: `--no-ff` for clean history
- **Graceful Failures**: Never leave system in corrupted state
- **Termination Safety**: Clear exit conditions prevent infinite loops

---

## Critical Fixes in This Version

1. ✅ **Commit format**: Now uses `--author` + HEREDOC + attribution
2. ✅ **Test DB migration**: Added `MIX_ENV=test mix db.migrate`
3. ✅ **PR merge**: New Phase 1 with `--no-ff` support
4. ✅ **Loop termination**: Cycle counting with max cycles
5. ✅ **Safety checks**: Pre-flight validation (Phase 0)
6. ✅ **Argument parsing**: Flags like `--pr-only`, `--auto-merge`
7. ✅ **Error handling**: Graceful failures with GitHub notifications
8. ✅ **CQRS/ES integration**: Full patterns in Phase 4

---

## Integration with Claude Code

This command uses:
- `gh` CLI for GitHub operations
- Standard `git` commands
- `mix` commands for testing and database operations
- Database management (SystemRepo, ProjectionsRepo, EventStore)
- Error handling and rollback procedures
- TodoWrite tool for progress tracking

**Workflow respects**:
- CQRS/Event Sourcing architecture from `docs/technical/CQRS_PATTERNS.md`
- Commit format from `CLAUDE.md`
- Project development standards from `docs/technical/DEVELOPMENT.md`
- Database patterns from `docs/technical/DATABASE_SCHEMA.md`
