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
   - `--max-cycles N`: Maximum workflow cycles (default: 5)
   - `--dry-run`: Show what would happen without executing
   - `--no-auto-merge`: Disable auto-merge for Claude PRs (legacy mode, not recommended)
   - `ISSUE_NUMBER`: Focus on specific issue (e.g., `42`)

   **Default Behavior** (no flags needed):
   - ✅ Auto-merge Claude's PRs (when tests pass or no CI)
   - ✅ Auto-continue through cycles (no "continue?" prompts)
   - ✅ Max 5 cycles before auto-exit
   - ✅ Process both PRs and issues

---

### Phase 1: Auto-Merge Ready PRs (with --no-ff)

**Purpose**: Automatically merge PRs created by Claude when tests pass, preserving merge history

**Philosophy**: Claude's PRs are auto-merged if safe. Human PRs require manual merge via GitHub UI.

**Auto-Merge Criteria**:
- PR author is Claude (ClaudeHaiku4-5, ClaudeSonnet4-5, ClaudeOpus4-5, anthropic-ai)
- AND (CI checks passed OR no CI configured)
- AND mergeable state is MERGEABLE

1. **Fetch all open PRs with complete metadata**:
   ```bash
   gh pr list --state open \
     --json number,title,author,reviewDecision,statusCheckRollup,mergeable,headRefName \
     --limit 50 > /tmp/open_prs.json
   ```

2. **Process each PR with auto-merge detection**:
   ```bash
   for pr_number in $(jq -r '.[].number' /tmp/open_prs.json); do
     # Get PR metadata
     author=$(gh pr view $pr_number --json author -q '.author.login')
     mergeable=$(gh pr view $pr_number --json mergeable -q '.mergeable')
     checks=$(gh pr view $pr_number --json statusCheckRollup -q '.statusCheckRollup[]?.conclusion')
     branch=$(gh pr view $pr_number --json headRefName -q '.headRefName')

     # Determine if Claude authored
     is_claude=false
     if [[ "$author" =~ ^(ClaudeHaiku4-5|ClaudeSonnet4-5|ClaudeOpus4-5|anthropic-ai)$ ]]; then
       is_claude=true
     fi

     # Determine if CI passed (or no CI)
     ci_passed=false
     if [[ -z "$checks" ]]; then
       # No CI configured - safe to merge
       ci_passed=true
     elif [[ "$checks" == "SUCCESS" ]] || ! echo "$checks" | grep -qv "SUCCESS"; then
       # All checks passed
       ci_passed=true
     fi

     # Auto-merge decision
     if [[ "$is_claude" == "true" ]] && [[ "$ci_passed" == "true" ]] && [[ "$mergeable" == "MERGEABLE" ]]; then
       echo "🤖 Auto-merging Claude PR #$pr_number..."

       # Merge with --no-ff (force merge commit)
       if gh pr merge $pr_number --merge --delete-branch; then
         echo "✅ Merged PR #$pr_number with merge commit"

         # Update local main
         git checkout main
         git pull origin main

         # Delete local branch if exists
         git branch -d "$branch" 2>/dev/null || true

         # Add success comment
         gh pr comment $pr_number --body "🎉 Auto-merged with merge commit (--no-ff)

Claude detected this as safe to merge:
- ✅ Authored by Claude
- ✅ CI checks passed (or no CI configured)
- ✅ Mergeable state confirmed

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude Opus 4.5 <noreply@anthropic.com>"

         PRS_MERGED=$((PRS_MERGED + 1))
         WORK_FOUND_THIS_CYCLE=true
       else
         # Merge failed - label and notify
         echo "❌ Merge failed for PR #$pr_number"
         gh pr edit $pr_number --add-label "merge-failed"
         gh pr comment $pr_number --body "⚠️ Auto-merge failed

Possible causes:
- Merge conflicts with main branch
- Protected branch rules not satisfied
- Outdated branch requiring rebase

Please resolve manually via GitHub UI.

🤖 Generated with [Claude Code](https://claude.com/claude-code)"

         echo "[$(date)] Phase 1: Merge failed for PR #$pr_number" >> /tmp/continue_todos_errors.log
       fi
     else
       # Not eligible for auto-merge
       echo "⏭️ Skipping PR #$pr_number (author: $author, ci: $ci_passed, mergeable: $mergeable)"
     fi
   done
   ```

3. **Summary after all PRs processed**:
   ```bash
   echo "=== Phase 1 Complete ==="
   echo "PRs auto-merged: $PRS_MERGED"
   echo "PRs skipped: $(jq length /tmp/open_prs.json) - $PRS_MERGED"
   ```

**Important Notes**:
- Human-authored PRs are NEVER auto-merged (require manual approval via GitHub UI)
- Failed merges are labeled and commented but don't block workflow
- Local branches are cleaned up automatically after successful merge
- All merges use `--no-ff` to preserve feature branch history

---

### Phase 1.5: Self-Healing Error Handler

**Purpose**: Automatically detect, fix, and update command syntax errors in this file

**Philosophy**: When bash commands fail, Claude updates this file with corrections and continues

**Trigger**: Any critical command failure in Phases 1-5

1. **Common Error Patterns and Fixes**:

   **Git Command Failures**:
   ```bash
   # Error: "fatal: not a git repository"
   # Fix: Ensure in repo root
   if ! git rev-parse --git-dir >/dev/null 2>&1; then
     cd /home/pof/code/balados/balados.sync || exit 1
   fi

   # Error: "fatal: branch already exists"
   # Fix: Force checkout existing branch
   git checkout -B $branch_name  # Instead of: git checkout -b

   # Error: "fatal: refusing to merge unrelated histories"
   # Fix: Add --allow-unrelated-histories flag
   git merge --allow-unrelated-histories origin/main
   ```

   **GitHub CLI Failures**:
   ```bash
   # Error: "GraphQL: Could not resolve to a PullRequest"
   # Fix: Verify PR exists before operations
   if gh pr view $pr_number >/dev/null 2>&1; then
     gh pr merge $pr_number
   else
     echo "PR #$pr_number not found, skipping"
   fi

   # Error: "HTTP 422: Validation Failed (pull request already merged)"
   # Fix: Check merge state first
   state=$(gh pr view $pr_number --json state -q '.state')
   if [ "$state" = "OPEN" ]; then
     gh pr merge $pr_number
   fi
   ```

   **Mix Command Failures**:
   ```bash
   # Error: "** (Mix) Could not start application"
   # Fix: Ensure database is up and migrated
   mix do db.create, db.migrate

   # Error: "** (DBConnection.ConnectionError)"
   # Fix: Start PostgreSQL service
   sudo systemctl start postgresql

   # Error: "** (ArgumentError) could not lookup Ecto repo"
   # Fix: Specify repo explicitly
   MIX_ENV=test mix ecto.migrate -r BaladosSyncProjections.ProjectionsRepo
   ```

2. **Self-Healing Mechanism**:

   ```bash
   # Wrapper function for critical commands
   self_healing_exec() {
     local command="$1"
     local context="$2"  # Phase name for logging

     # Execute command and capture output
     if ! output=$(eval "$command" 2>&1); then
       echo "[SELF-HEAL] Command failed in $context"
       echo "[SELF-HEAL] Command: $command"
       echo "[SELF-HEAL] Error: $output"

       # Determine fix based on error pattern
       fixed_command=""

       case "$output" in
         *"not a git repository"*)
           fixed_command="cd /home/pof/code/balados/balados.sync && $command"
           ;;
         *"branch already exists"*)
           fixed_command="${command/-b/-B}"  # Replace -b with -B
           ;;
         *"Could not resolve to a PullRequest"*)
           fixed_command="gh pr view \$pr_number >/dev/null 2>&1 && $command || echo 'PR not found'"
           ;;
         *"pull request already merged"*)
           fixed_command="[ \"\$(gh pr view \$pr_number --json state -q '.state')\" = 'OPEN' ] && $command"
           ;;
         *"Could not start application"*)
           fixed_command="mix do db.create, db.migrate && $command"
           ;;
         *"DBConnection.ConnectionError"*)
           fixed_command="sudo systemctl start postgresql && $command"
           ;;
       esac

       # Update this command file if fix determined
       if [ -n "$fixed_command" ]; then
         echo "[SELF-HEAL] Applying fix: $fixed_command"

         # Escape special chars for sed
         escaped_old=$(printf '%s\n' "$command" | sed 's/[[\.*^$/]/\\&/g')
         escaped_new=$(printf '%s\n' "$fixed_command" | sed 's/[[\.*^$/]/\\&/g')

         # Update the command file
         sed -i "s|$escaped_old|$fixed_command|g" \
           /home/pof/code/balados/balados.sync/.claude/commands/continue-todos.md

         # Log the self-healing action
         echo "[$(date)] Self-healed: $context - Updated command file" >> /tmp/continue_todos_self_heal.log
         echo "  Old: $command" >> /tmp/continue_todos_self_heal.log
         echo "  New: $fixed_command" >> /tmp/continue_todos_self_heal.log

         # Retry with fixed command
         if eval "$fixed_command" 2>&1; then
           echo "[SELF-HEAL] ✅ Fix successful, continuing workflow"
           return 0
         else
           echo "[SELF-HEAL] ❌ Fix failed, manual intervention needed"
           return 1
         fi
       else
         echo "[SELF-HEAL] ⚠️ No automatic fix available for this error"
         echo "[SELF-HEAL] Manual review required"
         return 1
       fi
     else
       # Command succeeded normally
       return 0
     fi
   }
   ```

3. **Usage in Other Phases**:

   ```bash
   # Wrap critical commands with self-healing
   # Example in Phase 1:
   self_healing_exec "gh pr merge $pr_number --merge --delete-branch" "Phase 1: PR Merge"

   # Example in Phase 4:
   self_healing_exec "MIX_ENV=test mix db.migrate" "Phase 4: Test DB Migration"

   # Example in Phase 5:
   self_healing_exec "gh pr create --title 'feat: ...' --body '...'" "Phase 5: PR Creation"
   ```

4. **Self-Healing Log Review**:

   ```bash
   # At end of workflow, report self-healing actions
   if [ -f /tmp/continue_todos_self_heal.log ]; then
     echo ""
     echo "=== Self-Healing Actions Taken ==="
     cat /tmp/continue_todos_self_heal.log
     echo ""
     echo "📝 Command file updated with fixes. Review changes:"
     echo "   git diff .claude/commands/continue-todos.md"
   fi
   ```

**Important Notes**:
- Self-healing only applies to known error patterns
- Unknown errors fail gracefully without workflow corruption
- All fixes are logged to `/tmp/continue_todos_self_heal.log`
- Command file updates are atomic (sed in-place)
- After self-healing, commit the updated command file for persistence

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

### Phase 6: Auto-Loop or Terminate (NO USER PROMPTS)

**Purpose**: Automatically continue workflow until termination conditions met. NO `read` commands. NO user interaction.

**Philosophy**: Workflow runs autonomously until natural stopping point. All decisions are automatic based on conditions.

1. **Increment cycle counter** (MANDATORY):
   ```bash
   CYCLE_COUNT=$((CYCLE_COUNT + 1))
   echo ""
   echo "=========================================="
   echo "Cycle $CYCLE_COUNT complete"
   echo "=========================================="
   ```

2. **Evaluate termination conditions IN ORDER**:

   **Condition 1: Max cycles reached - STOP IMMEDIATELY**
   ```bash
   if [ $CYCLE_COUNT -ge $MAX_CYCLES ]; then
     echo "✅ TERMINATED: Max cycles ($MAX_CYCLES) reached"
     echo ""
     echo "=== Final Summary ==="
     echo "Total cycles: $CYCLE_COUNT"
     echo "PRs merged: ${PRS_MERGED:-0}"
     echo "PRs updated: ${PRS_UPDATED:-0}"
     echo "Issues completed: ${ISSUES_COMPLETED:-0}"
     echo ""
     exit 0
   fi
   ```

   **Condition 2: Single issue mode completed - STOP IMMEDIATELY**
   ```bash
   if [ "$SINGLE_ISSUE" = true ] && [ -n "$COMPLETED_ISSUE" ]; then
     echo "✅ TERMINATED: Single issue mode - completed #$COMPLETED_ISSUE"
     echo ""
     echo "=== Summary ==="
     echo "Issue completed: #$COMPLETED_ISSUE"
     echo "Feature branch: $FEATURE_BRANCH"
     echo "PR created: YES"
     echo ""
     exit 0
   fi
   ```

   **Condition 3: PR-only mode with no open PRs - STOP IMMEDIATELY**
   ```bash
   if [ "$PR_ONLY" = true ]; then
     open_pr_count=$(gh pr list --state open --json number -q 'length')
     if [ "$open_pr_count" -eq 0 ]; then
       echo "✅ TERMINATED: PR-only mode - no more open PRs"
       echo ""
       echo "=== Summary ==="
       echo "PRs merged: ${PRS_MERGED:-0}"
       echo "PRs updated: ${PRS_UPDATED:-0}"
       echo ""
       exit 0
     fi
   fi
   ```

   **Condition 4: No work found for 2 consecutive cycles - STOP IMMEDIATELY**
   ```bash
   if [ "$WORK_FOUND_THIS_CYCLE" = false ]; then
     NO_WORK_CYCLES=$((NO_WORK_CYCLES + 1))
     echo "ℹ️ No work found this cycle (consecutive no-work count: $NO_WORK_CYCLES)"

     if [ $NO_WORK_CYCLES -ge 2 ]; then
       echo "✅ TERMINATED: No work found for 2 consecutive cycles"
       echo ""
       echo "=== Summary ==="
       echo "Total cycles: $CYCLE_COUNT"
       echo "PRs merged: ${PRS_MERGED:-0}"
       echo "PRs updated: ${PRS_UPDATED:-0}"
       echo "Issues completed: ${ISSUES_COMPLETED:-0}"
       echo ""
       exit 0
     fi
   else
     NO_WORK_CYCLES=0
   fi
   ```

3. **Auto-Continue to next cycle** (DEFAULT BEHAVIOR - no confirmation needed):
   ```bash
   echo ""
   echo "🔄 AUTO-CONTINUING to cycle $((CYCLE_COUNT + 1))"
   echo "   (Will terminate when: max cycles reached | no work for 2x | PR-only mode complete)"
   echo ""

   # Reset work flag for next cycle
   WORK_FOUND_THIS_CYCLE=false

   # Brief pause for log readability (optional)
   sleep 1

   # Jump back to Phase 1 for next cycle
   # (In actual implementation, use appropriate control flow for your script)
   ```

**CRITICAL NOTES**:
- ❌ NEVER use `read` command (no user input)
- ❌ NEVER ask "continue?" or "should I proceed?"
- ✅ ALWAYS log decisions and progress
- ✅ ALWAYS reset WORK_FOUND_THIS_CYCLE at cycle end
- ✅ ALWAYS follow condition order (first match wins)
- ✅ ALWAYS return to main branch before terminating

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

### Default Automation (Recommended)

```bash
# ✅ BEST: Full automation (all PRs + issues, auto-merge Claude PRs, 5 cycles max)
/continue-todos

# Auto-merge Claude PRs and handle feedback on existing PRs
/continue-todos --max-cycles 1

# Focus on specific issue with full automation
/continue-todos 42
```

### PR-Only Mode

```bash
# Merge all Claude PRs, skip new issues
/continue-todos --pr-only

# Merge Claude PRs only, run one cycle then exit
/continue-todos --pr-only --max-cycles 1
```

### Single-Issue Mode

```bash
# Work on one specific issue, create PR, then exit
/continue-todos 42 --single-issue

# Work on highest priority issue, create PR, then exit
/continue-todos --single-issue
```

### Advanced Options

```bash
# Disable auto-merge (legacy mode - not recommended)
/continue-todos --no-auto-merge

# Test dry run (show what would happen without executing)
/continue-todos --dry-run

# Custom cycle count
/continue-todos --max-cycles 3

# Combine multiple flags
/continue-todos 42 --single-issue --max-cycles 1
```

### What Each Flag Does

| Flag | Behavior |
|------|----------|
| (none) | ✅ Default: Auto-merge PRs + process issues, 5 cycles max |
| `--pr-only` | Only Phase 1-2 (merge + audit), skip Phase 3-5 (issues) |
| `--single-issue` | Work on ONE issue then auto-exit |
| `--max-cycles N` | Override default max cycles (5) |
| `--no-auto-merge` | Don't auto-merge Claude PRs (requires manual GitHub approval) |
| `--dry-run` | Show actions without executing |
| `ISSUE_NUMBER` | Focus on specific issue (e.g., `/continue-todos 42`) |

---

## Automation Guarantees 🎯

When you run `/continue-todos`:

### ✅ WILL DO (Automatic)

1. **Auto-Merge Claude's PRs**: If authored by Claude AND (tests pass OR no CI), merge immediately with `--no-ff`
2. **Auto-Continue Cycles**: Proceed through all 6 phases automatically without asking
3. **Auto-Fix Errors**: Detect bash command failures and update this file with corrections
4. **Auto-Terminate**: Exit automatically when: max cycles reached | no work for 2x | PR-only complete | single-issue done
5. **Auto-Cleanup**: Delete branches, reset work flags, return to main branch
6. **Auto-Log**: Track all decisions in progress logs and error files

### ❌ WILL NOT DO

1. **Ask "continue?"**: Zero user prompts about workflow continuation
2. **Merge Human PRs**: Only auto-merge Claude's PRs (humans need GitHub approval UI)
3. **Loop Forever**: Max 5 cycles default prevents runaway automation
4. **Leave Git Corrupted**: All failures rollback to clean state
5. **Ask Workflow Questions**: Never ask about proceeding, continuing, merging
6. **Skip Code Questions**: ALWAYS ask about implementation choices and architecture

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

### Automation First 🤖
- **Default Auto-Merge**: Claude's PRs merge automatically when safe (CI passed or no CI)
- **No User Prompts**: Workflow runs autonomously until termination conditions met
- **Self-Healing**: Command failures trigger automatic fixes and file updates
- **Continuation**: Automatically loop through phases until explicit stop criteria met
- **Silent Automation**: Run phases without "continue?" questions, provide progress logging

### CQRS/Event Sourcing ⚙️
- **Event Sourcing Adherence**: Commands/events follow patterns from `docs/technical/CQRS_PATTERNS.md`
- **Event Immutability**: Never modify events; emit new corrective events
- **Projection Safety**: Reset projections is safe operation (replays from events)
- **Mandatory for Changes**: All Phase 4 implementations MUST follow CQRS/ES patterns

### Git & Commit Hygiene 🌳
- **Merge Commits**: Always use `--no-ff` to preserve feature branch history
- **Atomic Commits**: Each commit is meaningful and tied to specific issue
- **Proper Attribution**: All commits include Claude Code footer and author metadata
- **Branch Cleanup**: Local and remote branches deleted after successful merge
- **Main Safety**: Always return to main branch before exiting

### Database Management 🗄️
- **Test DB Migration**: ALWAYS run `MIX_ENV=test mix db.migrate` before tests
- **Migration Verification**: Check pending migrations before proceeding
- **Repo Awareness**: Distinguish SystemRepo, ProjectionsRepo, EventStore operations
- **Critical**: Missing migrations cause test failures (non-negotiable)

### Error Handling & Safety 🛡️
- **Graceful Failures**: Never leave git in corrupted state
- **Rollback on Error**: Failed operations return to clean main branch
- **Partial Success**: Merge failures don't block processing other PRs
- **Error Logging**: All failures logged to `/tmp/continue_todos_errors.log`
- **Self-Healing Logs**: Track all fixes in `/tmp/continue_todos_self_heal.log`

### Termination Safety 🛑
- **Max Cycles**: Default 5 cycles prevents infinite loops
- **No Work Detection**: Exit after 2 consecutive cycles with no work
- **Mode-Specific Exits**: PR-only, single-issue modes have clear exit conditions
- **Clean Exits**: Always return to main branch before terminating
- **Order Matters**: Evaluate termination conditions in strict order

### User Interaction Philosophy 💬
- **Questions for Code Only**: Ask about implementation choices, architecture decisions, design tradeoffs
- **No Workflow Questions**: NEVER ask "should I continue?", "merge this PR?", "proceed with...?"
- **Silent Automation**: Run phases silently with progress logging instead
- **Summary Reports**: Provide detailed summary ONLY at termination
- **Code-Level Prompts**: Ask user questions about business logic, not automation

### Self-Healing Philosophy 🔧
- **Command Fixes**: Update this file when bash commands fail with known errors
- **Pattern Recognition**: Match error output to known fix patterns
- **Atomic Updates**: Use sed for safe in-place file modifications
- **Retry Logic**: Attempt fixed command once before failing
- **Log Everything**: Track all self-healing actions for review
- **Persistence**: Commit updated command file for future runs

---

## Improvements in This Version (v2)

1. ✅ **Auto-Merge Claude PRs**: Phase 1 now detects Claude authorship and merges automatically
2. ✅ **Self-Healing Errors**: New Phase 1.5 with `self_healing_exec()` for auto-corrections
3. ✅ **No User Prompts**: Phase 6 completely rewritten, ZERO `read` commands
4. ✅ **Auto-Continuation**: Workflow loops automatically between cycles (no "continue?" questions)
5. ✅ **Default Automation**: Auto-merge becomes default (no `--auto-merge` flag needed)
6. ✅ **Clear Termination**: Four explicit conditions (max cycles, no work, PR-only, single-issue)
7. ✅ **Code-Only Questions**: Automation never asks about workflow, only implementation
8. ✅ **File Self-Improvement**: Command file updates itself when commands fail with known errors

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
