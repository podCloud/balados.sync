# TODOS.md - Task Queue for Claude Code

<!-- INSTRUCTIONS FOR CLAUDE CODE
When reading this file, execute the following workflow:

## 1. Sync Tasks with GitHub

```bash
# Get current state
gh issue list --state open --json number,title,labels
gh pr list --state open --json number,title,headRefName
```

## 2. Process Each Task in TODO Section

For each task:
- Search for existing issue/PR matching the task description
- If found: Move to "In Progress" with link and status
- If NOT found: Create issue with `gh issue create`

## 3. Issue Creation Template

Use this format when creating issues - the body IS the prompt for Claude Code:

```bash
gh issue create \
  --title "<type>: <concise description>" \
  --label "<labels>" \
  --body "## Objective
<One sentence: what needs to be done>

## Context
<Why this matters, relevant files/modules>

## Implementation
1. <Step 1>
2. <Step 2>
3. <Step 3>

## Acceptance Criteria
- [ ] <Testable criterion 1>
- [ ] <Testable criterion 2>
- [ ] Tests pass: \`mix test\`

## References
- Docs: [ARCHITECTURE.md](docs/technical/ARCHITECTURE.md)
- Related: #<issue-number>"
```

## 4. Update In Progress Section

For tasks with issues/PRs, update status:
- `OPEN` - Issue created, not started
- `WIP` - PR exists, in development
- `REVIEW` - PR awaiting review
- `MERGED` - Complete, move to Done

## 5. Commit and Push

```bash
git add TODOS.md
git commit --author="Claude <noreply@anthropic.com>" -m "chore: sync TODOS.md with GitHub"
git push origin main
```

END INSTRUCTIONS -->

---

## TODO

<!-- Add tasks here. Format: `- [ ] <description>` -->
<!-- Claude Code will create GitHub issues for these -->



---

## In Progress

<!-- Claude Code maintains this section automatically -->
<!-- Format: `- [ ] <description> - [#N](link) - STATUS` -->



---

## Done

<!-- Move completed items here for reference, then periodically clean up -->

