# Phase 2 — System

Goal: turn the prose in `DESIGN.md` into machine-checkable tokens that live in
the project's own styling system, so Phase 3 can be written against names rather
than values.

## Where tokens go

Use what exists. Do not add a token library, a CSS-in-JS runtime, or a second
styling system to hold tokens.

| Project uses | Put tokens in |
| --- | --- |
| Tailwind | `tailwind.config.*` theme (v3) or `@theme` in the CSS entry (v4) |
| Plain CSS / CSS modules | `:root` custom properties in the global stylesheet |
| CSS-in-JS | The existing theme object |
| Design-token pipeline (Style Dictionary, DTCG) | The existing token JSON source |
| Native / RN | The existing theme constants module |
| Nothing yet | A single `tokens.css` with custom properties, imported first |

## Name by role, not by value

`--color-accent`, not `--color-orange-500`. `--space-section`, not `--space-96`.
A value-named token freezes a decision you will want to change; a role-named
token survives the redesign. A raw ramp (`--orange-500`) may exist underneath,
but components reference roles only.

Minimum role set:

```
surface, surface-raised, surface-sunken
ink, ink-muted, ink-inverse
edge, edge-strong
accent, accent-ink, accent-muted
positive, caution, negative  (+ their ink pairs)
focus
```

## Type scale

Write concrete values, not a formula. Pick a ratio deliberately (1.2 minor third
for dense UI, 1.25-1.333 for product, 1.5+ for editorial posters) then round to
sensible numbers and hand-adjust the display sizes.

For each step record: size, line-height, weight, letter-spacing, and what it is
for. Display sizes need negative tracking; small text needs positive tracking.
Line-height falls as size rises.

```
display   clamp(2.5rem, 6vw, 4.5rem) / 1.02 / 600 / -0.03em   hero only
h1        2rem   / 1.1  / 600 / -0.02em
h2        1.5rem / 1.2  / 600 / -0.01em
h3        1.25rem/ 1.3  / 600 / 0
body      1rem   / 1.6  / 400 / 0
small     0.875rem/1.5  / 400 / 0.005em
micro     0.75rem/ 1.4  / 500 / 0.02em   labels, eyebrows, uppercase
```

Set `font-optical-sizing: auto` for variable fonts. Load only the weights used;
every unused weight is wasted bytes.

## Spacing

A uniform 8px ramp applied everywhere is a slop tell — it produces even, rhythm-
less pages. Define spacing in two tiers:

- **Component tier**: 2, 4, 6, 8, 12, 16, 24 — inside buttons, cards, inputs.
- **Layout tier**: 32, 48, 64, 96, 128, 192 — between sections. Jumps here should
  be large. Compression between related blocks and a big gap between unrelated
  ones is what creates rhythm.

Related things sit closer than unrelated things. If every gap on the page is the
same, hierarchy is being carried by nothing.

## Radii, edges, elevation

- Define at most three radii: `radius-sm`, `radius-md`, `radius-lg`, plus `full`
  for pills. Nested surfaces must be concentric: outer = inner + padding.
- Borders communicate structure and state. Depth comes from layered shadows, not
  from a hairline border pretending to be elevation.
- Define elevation as a small named set (`shadow-raised`, `shadow-overlay`,
  `shadow-popover`) using multiple stacked transparent shadows, never a single
  blurry black blob.

## Motion

Tokenize duration and easing so timing is consistent:

```
duration-instant 100ms   duration-fast 150ms   duration-base 250ms   duration-slow 400ms
ease-out cubic-bezier(0.2, 0, 0, 1)      default for enter and exit
ease-in-out cubic-bezier(0.4, 0, 0.2, 1) for movement between two on-screen states
```

Every motion token must be neutralised under `prefers-reduced-motion: reduce`.

## Dark mode

If `DESIGN.md` calls for it, define dark as its own set of role values, not as an
inversion. Pure black backgrounds with pure white text are harsh; deep tinted
darks and slightly dimmed inks read better. Elevation in dark mode comes from
lighter surfaces, not from stronger shadows.

## Deliverable

1. Tokens written into the project's real config, with the role names above.
2. A short mapping table in `DESIGN.md` (or a sibling `TOKENS.md`) from role →
   value → where it is defined.
3. One rendered proof page or Storybook story showing the scale, palette, states,
   and elevation together. Screenshot it via Phase 4 and look at it before
   building real screens — mistakes are cheapest here.
