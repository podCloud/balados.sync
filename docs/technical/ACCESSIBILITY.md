# Accessibility (WCAG Compliance)

## Overview

Balados Sync aims for **WCAG 2.1 Level AA** compliance across all web-facing pages. This document covers the current compliance status, implemented patterns, and testing guidelines.

## Current Status

### Implemented (Level A & AA)

| Criterion | Status | Notes |
|-----------|--------|-------|
| **1.1.1** Non-text Content | Done | Alt text on images, `aria-hidden` on decorative SVGs |
| **1.3.1** Info and Relationships | Done | Semantic HTML (`<header>`, `<nav>`, `<main>`), form labels |
| **2.1.1** Keyboard | Done | Modal focus trap, Escape to close, tab navigation |
| **2.4.1** Bypass Blocks | Partial | `<main>` element present, no skip-to-content link yet |
| **2.4.2** Page Titled | Done | Each page has a descriptive `<title>` |
| **2.4.3** Focus Order | Done | Logical tab order, focus restored after modal close |
| **3.1.1** Language of Page | Done | `lang` attribute set dynamically from Gettext locale |
| **3.3.1** Error Identification | Done | Form errors displayed with styled messages |
| **4.1.2** Name, Role, Value | Done | ARIA attributes on modals, alerts, navigation |

### Known Gaps

| Item | Priority | Notes |
|------|----------|-------|
| Skip-to-content link | Nice-to-have | `<main>` exists but no explicit skip link |
| Color contrast audit | Should-do | No formal audit performed yet |
| Focus indicator visibility | Should-do | Tailwind `focus:ring-0` removes default ring |
| Clickable table rows | Nice-to-have | Need `role="button"` or keyboard interaction hints |

## Patterns Used

### Modal Dialogs

All modals follow the [WAI-ARIA Dialog pattern](https://www.w3.org/WAI/ARIA/apg/patterns/dialog-modal/):

```heex
<div role="dialog" aria-modal="true" aria-labelledby="modal-title" tabindex="0">
  <.focus_wrap id="modal-content">
    <h2 id="modal-title">Title</h2>
    <!-- content -->
    <button aria-label="Close">X</button>
  </.focus_wrap>
</div>
```

Key behaviors:
- `JS.focus_first()` moves focus into modal on open
- `JS.pop_focus()` restores focus to trigger on close
- `<.focus_wrap>` traps Tab within modal
- Escape key closes modal via `phx-window-keydown`

### Decorative vs Informative Images

```heex
<!-- Decorative: hidden from screen readers -->
<svg aria-hidden="true">...</svg>

<!-- Informative: has alt text -->
<img alt="Balados Sync" src={...} />
```

### Alerts and Status Messages

```heex
<div role="alert">
  <!-- Flash messages automatically announced by screen readers -->
</div>
```

### Language Navigation

```heex
<nav aria-label="Language">
  <a aria-current="true">FR</a>
  <a>EN</a>
</nav>
```

### Forms

All form inputs use Phoenix's component system with proper label association:

```heex
<.input field={@form[:name]} label="Name" type="text" />
```

This generates `<label for={id}>` with matching input `id`.

## Files with A11y Implementation

| File | What it covers |
|------|---------------|
| `core_components.ex` | Modal dialogs, forms, alerts, tables |
| `layouts/app.html.heex` | Language nav, logo alt, semantic structure |
| `layouts/root.html.heex` | `lang` attribute, `<main>` element |
| `assets/js/modals.ts` | Focus management, Escape key, click-away |

## Testing Guidelines

### Automated Testing

The project uses a WCAG-aware agent (`.claude/agents/web-accessibility-checker.md`) for automated reviews during PRs.

### Manual Testing Checklist

Use this checklist when making UI changes:

#### Keyboard Navigation
- [ ] All interactive elements reachable with Tab
- [ ] Focus order follows visual layout (left-to-right, top-to-bottom)
- [ ] Modals trap focus (Tab stays within modal)
- [ ] Escape closes modals and restores focus
- [ ] No keyboard traps (can always Tab away from elements)

#### Screen Reader (VoiceOver / NVDA)
- [ ] Page title announced on navigation
- [ ] Headings hierarchy is logical (h1 > h2 > h3)
- [ ] Form labels read correctly with inputs
- [ ] Decorative images are hidden (`aria-hidden="true"`)
- [ ] Modal role and title announced on open
- [ ] Alert messages announced automatically

#### Visual
- [ ] Focus indicators visible on all interactive elements
- [ ] Text readable at 200% zoom
- [ ] No information conveyed by color alone

### How to Test with VoiceOver (macOS)

1. Enable: Cmd + F5
2. Navigate: VO + Arrow keys (VO = Ctrl + Option)
3. Interact: VO + Space
4. Rotor (headings/links): VO + U

### How to Test with NVDA (Windows)

1. Download from [nvaccess.org](https://www.nvaccess.org/)
2. Navigate: Tab, Shift+Tab, Arrow keys
3. Headings: H key
4. Landmarks: D key
5. Forms: F key
