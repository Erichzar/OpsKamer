# Accessibility

Target WCAG 2.2 AA unless `DESIGN.md` states otherwise. Run the automated pass
first — it clears the mechanical failures so human-eye review can focus on the
things a tool cannot see.

```bash
node scripts/audit.mjs --url <url> --paths /,/pricing --widths 390,1440
```

Exit code 1 means at least one critical or serious violation. Fix those before
continuing the visual review.

## What automation catches

Missing alt text, unlabelled controls, contrast failures on static text, missing
form labels, bad heading order, duplicate ids, missing landmarks, invalid ARIA.
Roughly a third of real accessibility problems. Passing axe is the floor, not
the goal.

## What you must check by hand

**Contrast in context** — automation tests static pairs. Check text over images
and gradients, disabled-state text, placeholder text, and text on the accent
color. Body text 4.5:1, large text (18.66px bold / 24px) 3:1, UI boundaries and
focus indicators 3:1.

**Focus** — tab through the whole page. Every interactive element must show a
visible focus ring that is not clipped by `overflow: hidden` and meets 3:1
against both the component and the adjacent background. Order must follow the
visual layout. No traps. Never `outline: none` without a replacement.
WCAG 2.2 adds *Focus Not Obscured*: sticky headers and cookie bars must not cover
the focused element.

**Keyboard** — every mouse interaction has a keyboard path. Escape closes
overlays. Focus moves into a modal on open and returns to the trigger on close.
Custom widgets follow the expected key patterns (arrows in menus, tabs, listboxes).

**Not by color alone** — status, validation, chart series, and required fields
need a shape, icon, pattern, or text label in addition to color.

**Motion** — `prefers-reduced-motion: reduce` neutralises every non-essential
animation. No parallax or auto-playing motion that cannot be paused. Nothing
flashes more than three times per second.

**Zoom and reflow** — 320px width and 200% zoom without horizontal scrolling or
clipped content. Text must survive 200% text-only zoom.

**Targets** — WCAG 2.2 *Target Size (Minimum)* is 24x24 CSS px; use 44x44 for
touch. Adjacent targets must not overlap.

**Semantics** — one `h1`, no skipped heading levels, real landmarks
(`header`/`nav`/`main`/`footer`), lists as lists, tables with headers, buttons
that are `<button>` and links that are `<a href>`.

**Content** — images have alt text that conveys purpose (decorative images get
`alt=""`), form errors say what went wrong and how to fix it, labels are visible
and not placeholder-only, and the language is declared on `<html>`.

**Screen reader spot-check** — for anything custom or dynamic, verify the
announcement. Live regions for async status. Do not ship a custom widget you
never listened to.

## Report

List violations by impact with rule id, location, and the fix. State plainly
which manual checks you performed and which you did not. "axe passed" alone is
not an accessibility report.
