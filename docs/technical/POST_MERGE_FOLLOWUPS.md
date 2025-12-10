# Post-Merge Follow-up Issues Strategy

## Overview

When a PR is approved and merged, code reviews often identify follow-up work that should be completed later. Instead of leaving this feedback in PR comments, we create explicit GitHub issues to:

1. **Track improvements** in the backlog
2. **Prevent hidden debt** from accumulating in closed PRs
3. **Prioritize work** based on impact (tests, security, optimizations)
4. **Maintain transparency** about why work exists

## Philosophy

> "Never leave review feedback as comments. Convert it to actionable issues."

This ensures all improvement ideas are:
- Properly tracked in the issue backlog
- Assigned a priority (MUST-FIX vs NICE-TO-HAVE)
- Visible in project metrics
- Not lost when PRs are closed

## Categories & Prioritization

### MUST-FIX (Phase-2, Critical Priority)

**When**: PRs merged with significant gaps that affect production use

**Examples**:
- Missing test coverage for critical paths
- Missing logging for audit trails
- Security validation gaps
- Breaking changes without migration path
- Documentation incomplete for public APIs

**Action**: Create issue immediately, label `phase-2`, assign high priority

### SHOULD-FIX (Phase-2, High Priority)

**When**: PRs merged with improvements needed for maintainability

**Examples**:
- Error handling gaps
- Input validation missing
- Logging for debugging
- Database index optimization
- Backward compatibility concerns

**Action**: Create issue with `phase-2`, medium priority

### NICE-TO-HAVE (Phase-3, Enhancement Priority)

**When**: PRs merged with optional improvements for performance/UX

**Examples**:
- Performance optimizations (async_stream, caching)
- Refactoring opportunities
- UX enhancements
- Rate limiting
- Documentation improvements

**Action**: Create issue with `phase-3`, tag as `enhancement`

## Integration with Development Workflow

Post-merge follow-up creation is integrated into `development-workflow` agent Phase 1: Merge Ready PRs.

This ensures the workflow is complete: PR merge → feedback capture → backlog update → future implementation.

## Quick Reference

| What | Phase | Label |
|------|-------|-------|
| Test coverage gaps | phase-2 | `follow-up`, `phase-2`, `test` |
| Missing logging | phase-2 | `follow-up`, `phase-2` |
| Security gaps | phase-2 | `follow-up`, `phase-2` |
| Error handling | phase-2 | `follow-up`, `phase-2` |
| Performance opt. | phase-3 | `follow-up`, `phase-3`, `enhancement` |
| Refactoring | phase-3 | `follow-up`, `phase-3`, `enhancement` |
| UX improvement | phase-3 | `follow-up`, `phase-3`, `enhancement` |

## Related Documentation

- [Development Workflow Agent](/.claude/agents/development-workflow.md) - Phase 1: Merge Ready PRs
- [CLAUDE.md](../CLAUDE.md) - Workflow and commit guidelines
- [CQRS Patterns](./CQRS_PATTERNS.md) - Architecture patterns for implementation
