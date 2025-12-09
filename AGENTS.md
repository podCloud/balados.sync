# Custom Agents for Balados Sync

Custom agents configured for this project. Agents provide specialized expertise and can be invoked explicitly or automatically by Claude when relevant.

## Available Agents

### development-workflow
Manages complete development cycles including PR merging, code review fixes, issue prioritization, solution implementation, and pull request creation. Uses natural language interaction instead of CLI flags.

- **When to use**: "Continue with the next issue", "What should we work on?", "Handle issue 42"
- **Follows**: CQRS/Event Sourcing patterns, atomic commits, test DB migrations
- **Location**: `.claude/agents/development-workflow.md`

---

### Architecture & Code Review

- **backend-architect** - Backend systems, APIs, databases, scalability
- **frontend-developer** - React, UI components, state management, accessibility
- **fullstack-developer** - End-to-end application and database design
- **architect-review** - Architectural consistency, SOLID principles, maintainability

---

### Specialized Expertise

- **typescript-pro** - Advanced TypeScript, strict typing, complex types
- **javascript-pro** - Modern JavaScript, async patterns, Node.js APIs
- **prompt-engineer** - LLM prompt optimization and AI feature building
- **test-engineer** - Test automation, coverage analysis, CI/CD
- **documentation-expert** - Technical writing and documentation standards

---

### Content & Tools

- **content-marketer** - Blog posts, social media, SEO strategy
- **web-accessibility-checker** - WCAG compliance, accessibility testing
- **nosql-specialist** - MongoDB, Redis, schema design, performance
