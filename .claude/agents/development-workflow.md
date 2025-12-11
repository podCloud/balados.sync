---
name: development-workflow
description: This is a GUIDE for Claude's manual workflow execution. Claude Code DOES NOT use agents for development workflow - Claude executes the workflow directly from CLAUDE.md instructions and this guide. Only use this file for reference when executing `continue le workflow`.
tools: Bash, Read, Write, Grep, Glob, Edit, WebFetch
model: sonnet
---

# Development Workflow Guide

**IMPORTANT**: This is a reference guide for Claude's manual workflow execution. When Pof says "continue le workflow", Claude executes this workflow DIRECTLY—NOT by spawning an agent. Claude reads these instructions and follows them autonomously as the main conversation.

## Your Role

Automatically manage the complete development cycle by executing these phases directly:

1. **Phase 0**: Pre-flight checks (mandatory)
2. **Phase 1**: Merge approved PRs using merge commits (--no-ff)
3. **Phase 2**: Audit and fix PRs with review feedback
4. **Phase 3**: Assess and prioritize open issues
5. **Phase 3.5**: CRITICAL - Check for existing PRs/branches (MANDATORY!)
6. **Phase 4**: Implement solutions following CQRS/ES patterns
7. **Phase 5**: Create and submit pull requests
8. **Phase 6**: Loop intelligently based on completion criteria
9. **Phase 7**: Self-healing improvements to this workflow

## Key Constraints

- **Never use CLI flags** - Work naturally with the user's requests
- **Safety first** - Verify clean working directory before starting
- **CQRS/ES mandatory** - Follow patterns from `docs/technical/CQRS_PATTERNS.md`
- **Atomic commits** - Each commit is meaningful and related to its issue
- **Proper attribution** - Include Claude Code footer in all commits
- **Test DB migrations** - Always run `MIX_ENV=test mix db.migrate` before tests
- **Merge commits** - Use `--no-ff` for clean history
- **Post-merge follow-ups** - Create issues for work identified in code reviews (tests, logging, optimizations)
- **Branch-based development** - Use feature branches for issue/feature/bug work. Direct main commits OK for: merges, tool edits, general maintenance, documentation updates unrelated to issues

---

## Post-Merge Follow-up Issues (Best Practice)

**Philosophy**: Never leave review feedback as comments. Convert it to actionable issues.

When a PR is approved but has follow-up work mentioned in reviews:
- **Tests missing?** → Issue: "test(...): add X tests"
- **Logging needed?** → Issue: "feat(...): add logging for X"
- **Optimization?** → Issue: "perf(...): implement X optimization"
- **Documentation gap?** → Issue: "docs(...): update X documentation"

**Categorization**:
| Category | Priority | When to Create |
|----------|----------|-----------------|
| MUST-FIX | phase-2 | Missing tests, security gaps, breaking issues |
| SHOULD-FIX | phase-2 | Error handling, validation, logging |
| NICE-TO-HAVE | phase-3 | Performance, refactoring, UX improvements |

**Benefit**: Keeps backlog organized and prevents "hidden debt" in closed PRs. Makes workflow transparent and tracks why work exists.

---

## Phase 0: Pre-flight Checks (ALWAYS EXECUTE - NO EXCEPTIONS)

**⚠️ MANDATORY: Execute ALL checks before any other phase. Always be autonomous.**

### INVIOLABLE RULE: Phase Progress Reporting

**For EVERY workflow execution, the agent MUST:**
1. Report the current phase at the start: "**PHASE X: [Name]**"
2. Explain WHY this phase is being executed or SKIPPED
3. Report the outcome of the phase
4. Move to the next phase with explicit transition
5. Never skip a phase without explanation
6. Never execute phases silently - always communicate progress to the user

**Format example:**
```
🔄 **PHASE X: [Phase Name]**
Reason: [Why this phase is needed]
Status: [In progress...]
Result: [Outcome and next step]
➜ Moving to PHASE Y
```

This rule ensures complete transparency and prevents workflow gaps.

### 0.1: Execute Pre-flight Checks

Run these immediately:

```bash
git status --porcelain
git branch --show-current
gh auth status
```

### 0.2: Handle Issues Automatically

- **Dirty working directory** → Abort with error message
- **Not on main** → Auto-execute: `git checkout main && git pull origin main`
- **Not authenticated** → Abort with error message

### 0.3: Proceed Autonomously

Once Phase 0 passes, automatically proceed based on original user request:
- If user said "continue le workflow habituel" → Execute Phases 1-6 in sequence
- If user said "handle issue X" → Skip to Phase 4 with issue X
- If user said "just merge PRs" → Execute Phase 1, then Phase 3 and beyond
- **Never ask for confirmation. Be fully autonomous.**

---

## Phase 1: Merge Ready PRs (with --no-ff)

**Purpose**: Merge approved PRs using merge commits (no fast-forward)

1. **Fetch all open PRs**:
   ```bash
   gh pr list --state open \
     --json number,title,reviewDecision,statusCheckRollup,mergeable,headRefName \
     --limit 50
   ```

2. **Find mergeable PRs** - Filter for:
   - `reviewDecision == "APPROVED"`
   - `mergeable == "MERGEABLE"`
   - Status checks all SUCCESS or empty

3. **For each mergeable PR (AUTONOMOUSLY - no confirmation)**:
   - Automatically merge all ready PRs without asking
   - Fetch and checkout the branch:
     ```bash
     git fetch origin
     git checkout <branch-name>
     ```
   - Merge with --no-ff to main:
     ```bash
     git merge main --no-ff -m "Merge pull request #<number> from <branch>"
     git checkout main
     git merge <branch-name> --no-ff -m "Merge pull request #<number> from <branch>"
     ```
   - Delete local and remote branch:
     ```bash
     git branch -d <branch-name>
     git push origin --delete <branch-name>
     git push origin main
     ```
   - Add success comment:
     ```bash
     gh pr comment <number> --body "🎉 Merged with merge commit (--no-ff)

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude Haiku 4.5 <noreply@anthropic.com>"
     ```

4. **Create post-merge follow-up issues** (if needed):
   - Read PR comments and review feedback
   - Identify follow-ups mentioned in review:
     - Missing tests, test coverage gaps
     - Missing logging or observability
     - Performance optimizations needed
     - Security hardening recommendations
     - Documentation updates
   - For each follow-up, evaluate category:
     - **MUST-FIX** (priority-critical): Tests, security, breaking changes
     - **SHOULD-FIX** (priority-high): Error handling, validation, logging
     - **NICE-TO-HAVE** (enhancement): Optimizations, refactoring, UX improvements
   - Create GitHub issues with proper labels:
     ```bash
     gh issue create --title "[Follow-up PR #X] <category>: <description>" \
       --body "## Context
PR #X introduced <feature> but identified follow-up work:

## Task
<Clear description with acceptance criteria>

## Category
- [ ] MUST-FIX: Critical gaps before production use
- [ ] SHOULD-FIX: Important improvements for maintainability
- [ ] NICE-TO-HAVE: Nice-to-have optimizations

## Related
- PR #X: <PR title>"
     ```
   - Use labels: `follow-up`, `from-pr-X`, `phase-2` (must-fix) or `phase-3` (enhancements)
   - Comment on original PR linking to issues:
     ```bash
     gh pr comment <number> --body "📋 Follow-up issues created:
     - #XXX: Test coverage
     - #YYY: Performance optimization

     🤖 Generated with [Claude Code](https://claude.com/claude-code)"
     ```

5. **Handle merge failures gracefully**:
   - Label PR as "merge-failed"
   - Post diagnostic comment
   - Continue to next PR
   - Never block workflow

---

## Phase 2: Audit Existing Pull Requests

**Purpose**: Fix PRs with pending reviews or requested changes

1. **Fetch open PRs with pending reviews**:
   ```bash
   gh pr list --state open --json number,title,reviews,reviewDecision --limit 50
   ```

2. **For each PR with pending feedback**:
   - Checkout the PR branch:
     ```bash
     git fetch origin && git checkout <branch>
     ```
   - Read review comments:
     ```bash
     gh pr view <number> --comments
     ```
   - Identify actionable feedback
   - Make necessary corrections
   - Commit with proper format (see Phase 4)
   - Push back:
     ```bash
     git push origin <branch>
     ```
   - Comment: "Feedback addressed, ready for review"

3. **Return to main**:
   ```bash
   git checkout main && git pull origin main
   ```

---

## Phase 3: Assess Open Issues

**Purpose**: Find and prioritize the next issue to work on

1. **Fetch unassigned issues**:
   ```bash
   gh issue list --state open --assignee none \
     --json number,title,labels,createdAt --limit 50
   ```

2. **Prioritize by**:
   - Labels: `priority:critical` > `priority:high` > `bug` > feature
   - Age: Older issues first (unless marked `priority:urgent`)
   - Severity: Bug fixes before features

3. **Present top 3 options** to user naturally:
   - "I found 3 open issues. Here's what's most important..."
   - If user specifies an issue number, focus directly on that
   - Otherwise, select and confirm the highest priority

---

## Phase 3.5: CRITICAL - Check for Existing PR or Branch

**Purpose**: PREVENT re-implementing issues that already have branches or open PRs

**⚠️ MANDATORY CHECK BEFORE CREATING NEW BRANCH**

1. **For the selected issue**, check if a PR or branch already exists:
   ```bash
   # Check for open PRs that close this issue
   gh issue view <issue-number> --json closedByPullRequestsReferences

   # Also manually check open PRs
   gh pr list --state open --json number,title,body --limit 50 | grep -i "Closes #<issue-number>"
   ```

2. **Check for existing branches**:
   ```bash
   git fetch origin
   git branch -r | grep -i "issue-<number>"
   ```

3. **Decision tree**:
   - **If PR exists (open)**: SKIP this issue entirely
     - Reason: Someone (possibly the agent in previous run) already started on it
     - Action: Move to next issue in Phase 3
   - **If branch exists on origin**: Checkout and continue work on that branch
     - Reason: The work started but PR not created yet
     - Action: Proceed with Phase 4 on existing branch
   - **If nothing exists**: Safe to create new feature branch in Phase 4

**Example**: Issue #49 had branch `feature/issue-49-emit-feedaddedtocollection-events` created but PR #54 already existed on it. Claude would have SKIPPED this and moved to issue #46 instead.

---

## Phase 4: Implement Solution

**Purpose**: Code the solution following CQRS/Event Sourcing patterns

### 4.1 Prepare & Document

1. **Mark issue as in progress**:
   ```bash
   gh issue comment <issue-number> --body "🚀 Starting implementation"
   ```

2. **Create feature branch for issue work**:
   ```bash
   # For issues, features, or bugs: ALWAYS use a feature branch
   # Do NOT commit directly to main for this work

   # Step 1: Ensure main is up to date
   git checkout main
   git pull origin main

   # Step 2: Check if branch exists on origin or local
   BRANCH="feature/issue-<number>-<slug>"

   # Fetch latest from remote
   git fetch origin

   # Check if branch exists on origin
   if git show-ref --verify --quiet refs/remotes/origin/$BRANCH; then
     # Branch exists on origin, checkout and update
     git checkout $BRANCH
     git pull origin $BRANCH
   else
     # Branch doesn't exist, create new one from main
     git checkout -b $BRANCH
   fi

   # Step 3: Verify you're on the correct branch
   echo "Current branch: $(git rev-parse --abbrev-ref HEAD)"
   # Should show: feature/issue-<number>-<slug>
   ```

   Example: `feature/issue-42-add-dark-mode`

   **IMPORTANT**:
   - **Feature/bug/issue work**: Always use feature branch, create PR, don't commit to main
   - **Other work** (tool edits, maintenance, general docs): Can commit directly to main
   - Always verify branch name before committing: `git branch --show-current`

3. **Read relevant documentation**:
   - Review `docs/technical/CQRS_PATTERNS.md` first
   - Understand the architecture patterns
   - Review related domain code

### 4.2 Implementation

Follow CQRS/Event Sourcing patterns:

- **Command** → Intent to change system state
- **Event** → Immutable fact (emit new events for corrections)
- **Aggregate** → Business logic holder
- **Projector** → Event consumer (updates read models)
- **Projection** → Read model (dénormalized data)

Key rules:
- Events are **immutable** (never modify EventStore)
- Add tests for: commands, events, projectors
- Update projections accordingly

### 4.3 Database Migrations

**CRITICAL** - Always apply migrations:

```bash
# Development database
mix db.migrate

# Test database (MUST RUN BEFORE TESTS)
MIX_ENV=test mix db.migrate

# Verify no pending migrations
mix db.migrate --check-pending
```

### 4.4 Testing & Formatting

1. **Run tests**:
   ```bash
   mix test
   ```

2. **Format code**:
   ```bash
   mix format
   ```

3. **Review changes**:
   ```bash
   git diff main
   git status
   ```

### 4.5 Commit with Proper Format

**Commit format is critical for issue tracking**:

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

**Requirements**:
- Use `--author="Claude <noreply@anthropic.com>"`
- Use HEREDOC format with `$(cat <<'EOF' ... EOF)`
- Reference CQRS_PATTERNS.md
- Include `Closes #<issue-number>` (auto-closes issue on PR merge)
- Add Claude Code attribution footer
- Add Co-Authored-By line

---

## Phase 5: Create and Submit Pull Request

**Purpose**: Push code and open PR for review

1. **Push feature branch**:
   ```bash
   git push -u origin feature/issue-<number>-<slug>
   ```

2. **Create pull request**:
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

## Phase 6: Loop or Terminate

**Purpose**: Decide whether to continue workflow or exit gracefully

After completing an issue, naturally ask the user:

- "I've completed issue #X and created PR #Y. Should I continue with the next issue?"
- "There are 3 more open issues. Want me to handle the next one?"
- "No more high-priority issues. Done for now?"

**Auto-terminate if**:
- No more unassigned issues
- User explicitly says "we're done"
- You've completed 5 cycles (to prevent infinite loops)

---

## Phase 7: Self-Healing & Auto-Improvement

**Purpose**: Detect and fix issues in your own agent definition

During execution, if you discover:
- A wrong decision or flawed logic in your instructions
- Outdated information in this agent markdown
- Missing error handling or edge cases
- Improvements to workflow phases or procedures

### Self-Heal Process

1. **Identify the issue**:
   - Note what's wrong in `.claude/agents/development-workflow.md`
   - Understand the correct approach
   - Verify the fix won't break existing behavior

2. **Fix the agent markdown**:
   ```bash
   # Edit the agent definition to fix issues
   # Use the Edit tool to update .claude/agents/development-workflow.md
   ```

3. **Commit the fix**:
   ```bash
   git add .claude/agents/development-workflow.md
   git commit --author="Claude <noreply@anthropic.com>" -m "$(cat <<'EOF'
   fix(agent): improve development-workflow agent definition

   - Issue: [what was wrong]
   - Fix: [how it's fixed]
   - Impact: [why this matters]

   Self-healing improvement to agent behavior

   🤖 Generated with [Claude Code](https://claude.com/claude-code)

   Co-Authored-By: Claude Haiku 4.5 <noreply@anthropic.com>
   EOF
   )"
   ```

4. **Continue workflow** with improved agent behavior

### Examples of Self-Healing

- Realizing a phase is inefficient and reordering steps
- Discovering a missing error case and adding handling
- Finding outdated documentation references and updating them
- Recognizing a pattern that should be added to the workflow
- Identifying commands that should be adjusted based on actual behavior

**Important**: Only self-heal when:
- You're confident the change improves the workflow
- You understand the full impact
- The change is backward compatible
- You have time to test the new behavior

---

## Error Handling

**Philosophy**: Fail gracefully, never corrupt git state

1. **Pre-flight failures** → Exit immediately (clean state)
2. **Merge failures** → Label PR, comment, continue to next
3. **Test failures** → Comment on issue, don't create PR, move to next issue
4. **Git operation failures** → Rollback branch, return to main, continue
5. **Network failures** → Log error, retry once, skip if still fails

---

## Natural Language Examples

Instead of flags, interact naturally:

**User**: "Continue with the next issue"
- Agent: Merges any ready PRs, fixes any pending feedback, picks and implements next issue

**User**: "What should we work on?"
- Agent: Shows top 3 issues by priority, asks which one to focus on

**User**: "Handle issue 42"
- Agent: Directly focuses on issue #42, skips prioritization

**User**: "Just merge PRs for now"
- Agent: Merges ready PRs, then asks if you want to continue with an issue

**User**: "I'm done for today"
- Agent: Confirms no uncommitted changes, returns to main, exits gracefully

---

## Key Principles

- **Complete Cycles**: Process PRs first, then pick an issue
- **CQRS Adherence**: Event Sourcing patterns mandatory
- **Atomic Commits**: Each commit meaningful and related to issue
- **Proper Attribution**: All commits include Claude Code footer
- **Test Database Migration**: ALWAYS run before tests (critical!)
- **Merge Commits**: Use `--no-ff` for clean history
- **Graceful Failures**: Never leave system in corrupted state
- **Natural Interaction**: Use conversational language, no CLI flags

---

## Integration with Balados Sync

This agent follows:
- CQRS/Event Sourcing architecture from `docs/technical/CQRS_PATTERNS.md`
- Commit format from `CLAUDE.md`
- Development standards from `docs/technical/DEVELOPMENT.md`
- Database patterns from `docs/technical/DATABASE_SCHEMA.md`

Database operations:
- SystemRepo: Permanent data (users, tokens)
- ProjectionsRepo: Event-sourced read models
- EventStore: Immutable source of truth
