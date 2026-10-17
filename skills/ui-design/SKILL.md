---
name: ui-design
description: >-
  Art-direction and visual-quality engine for any web UI, in any stack. Use when building a new interface, redesigning an existing one, choosing a palette/typography/layout direction, building a design system or design tokens, reviewing a UI for polish or accessibility, or when a design "looks AI-generated", "feels generic", "feels off", or needs to stop looking templated. Drives a four-phase loop: direction -> tokens -> build -> screenshot review. Triggers on UI design, visual design, art direction, design system, design tokens, landing page, redesign, anti-slop, AI slop, look and feel, brand, typography, palette, spacing, accessibility audit, WCAG, visual review.
license: MIT (see references/sources.md for vendored material and attribution)
---

# UI Design

You are the design engineer. The human is the art director. This skill exists to
stop you producing the default templated interface that every model reaches for,
and to replace taste-by-accident with an explicit, written, per-project direction
that you then verify against real rendered pixels.

This skill is stack-agnostic on purpose. It never assumes React, Tailwind, or any
framework. Detect what the project already uses and express every decision in
that system.

## The one hard rule

**Do not write UI code until `DESIGN.md` exists for this project and the human has
accepted it.** A brief you invented silently is not a direction. If `DESIGN.md` is
missing, run Phase 1 and stop for confirmation.

Exception: a one-line fix to existing UI that changes no visual decision.

## Phases

| Phase | Do this | Reference |
| --- | --- | --- |
| 1. Direction | Interview or ingest references, then write `DESIGN.md` | [direction.md](references/direction.md), [style-vocabulary.md](references/style-vocabulary.md) |
| 2. System | Turn `DESIGN.md` into real tokens in the project's own styling system | [design-system.md](references/design-system.md) |
| 3. Build | Implement using tokens only, applying polish rules as you go | [polish.md](references/polish.md) |
| 4. Review | Screenshot, look at the pixels, score, fix, repeat | [review.md](references/review.md), [accessibility.md](references/accessibility.md) |

Invoke a single phase with an argument: `direction`, `system`, `build`, `review`,
`quick` (review, HIGH/MEDIUM only), or `audit` (accessibility only). With no
argument, start at the earliest phase whose output is missing.

## Step 0: detect the ground truth

Before anything else, establish and state:

1. **Styling system** — read `package.json`, config files, and 2-3 existing
   components. Tailwind, CSS modules, plain CSS, CSS-in-JS, native styles?
   Never introduce a second styling system to apply a fix.
2. **Token home** — where do colors/spacing/type live today? A theme config, CSS
   custom properties, a constants file, or nowhere?
3. **Component inventory** — is there a UI library (shadcn, MUI, Radix, Chakra)?
   Match its conventions instead of fighting them.
4. **Existing `DESIGN.md`** — project root, `docs/`, or `.design/`.

State these four findings in one short block before proceeding. If the project is
empty, say so and go straight to Phase 1.

## Anti-slop rules

These are the tells that mark an interface as machine-generated. Treat each as
forbidden unless `DESIGN.md` explicitly argues for it:

- Purple/indigo-to-pink gradients, or any gradient used as the primary brand device.
- Everything centered. Center a hero if it earns it; do not center an entire page.
- One border radius applied uniformly to every surface.
- Inter (also: Geist, system-ui default stacks) as the display face by default.
- Emoji as iconography.
- Glassmorphism/backdrop-blur cards floating on a blurred blob background.
- Three feature cards in a row with a small icon, a bold title, and two lines of grey text.
- Dark mode as `#0a0a0a` background with `#fafafa` text and a violet accent.
- Generic copy: "Seamlessly", "Effortlessly", "Supercharge your workflow", "Built for teams".
- Uniform 8px-scale spacing with no rhythm, no compression, no large jumps.

Violating one of these on purpose, in service of a stated direction, is fine.
Violating all of them at once is the AI look.

## Non-negotiable quality floor

Independent of style direction:

- Text contrast meets WCAG 2.2 AA (4.5:1 body, 3:1 large text and UI boundaries).
- Every interactive element has visible focus, hover, active, and disabled states.
- Nothing is conveyed by color alone.
- Keyboard reachable in a sensible order; no keyboard traps.
- `prefers-reduced-motion` honored for every non-essential animation.
- Layout survives 320px width and 200% browser zoom.
- Empty, loading, and error states exist for every data-driven surface.

## Verification loop (Phase 4)

Never claim a UI is good without looking at it. Screenshots are attachments the
model can actually see — use them.

```bash
# from the skill directory
node scripts/shoot.mjs --url http://localhost:5173 --out ./shots
node scripts/shoot.mjs --url http://localhost:5173 --out ./shots --widths 390,768,1440 --dark
node scripts/audit.mjs --url http://localhost:5173        # axe-core WCAG pass
```

Then `read` each PNG, and score it against [review.md](references/review.md).
Iterate: shoot, look, score, fix, re-shoot. Two rounds minimum. Stop when the
scorecard has no HIGH findings and the direction in `DESIGN.md` is legible in the
pixels.

Run `node scripts/shoot.mjs --help` before customising; do not read the script
source unless you need to change its behavior.

### If this session cannot see images

Screenshot review requires a tool that returns image content, not a path. If the
current session has no image-capable read tool, do not fall back to reasoning
about the CSS — that is how templated interfaces get approved.

Delegate the inspection instead, to an agent profile whose tool list names `read`
explicitly (in pi, `explore` does; profiles declared as `tools: "*"` only inherit
whatever the parent session actually has). Hand it the absolute PNG paths and the
review contract, and have it return the scorecard.

Decoding the PNG by hand is a last resort. It works and produces measurable
evidence, but it costs roughly ten times the tokens and time of looking at the
picture, and it cannot judge whether the result feels right.

## Handoff

When the work is done, report: the direction in one sentence, the token file
paths, the screenshots reviewed, the scorecard verdict, and anything in
`DESIGN.md` you were unable to honor and why.
