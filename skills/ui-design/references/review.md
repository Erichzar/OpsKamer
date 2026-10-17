# Phase 4 — Review

Never assert that an interface is good without looking at rendered pixels. This
phase is the difference between a plausible-looking codebase and a finished
interface.

## Loop

```bash
node scripts/shoot.mjs --url <url> --paths /,/pricing --widths 390,768,1440 --dark --out ./shots
```

Then `read` every PNG listed under `SCREENSHOTS:`. Actually look at them. Score,
fix, re-shoot. **Two rounds minimum.** The first round finds structural problems;
the second finds the ones the first round created.

Also run `node scripts/audit.mjs --url <url>` and fix everything critical or
serious before spending review effort on taste.

## What to look for, in order

Work top-down. A page with broken hierarchy cannot be fixed with better shadows.

1. **Does the direction survive contact?** Open `DESIGN.md`. Could a stranger
   name the style from this screenshot alone? If the shot could belong to any
   other product, the direction did not make it into the pixels. This is the most
   important question and the one most often skipped.
2. **Hierarchy** — squint at the shot (or scale it down mentally). What reads
   first, second, third? Is that the intended order? If everything is the same
   weight and size, nothing is emphasised.
3. **Rhythm and grouping** — are related things closer than unrelated things? Are
   section gaps meaningfully larger than component gaps, or is the whole page on
   one flat spacing ramp?
4. **Alignment** — pick an edge and trace it down the shot. Do things line up, or
   are there near-misses that read as sloppiness?
5. **Type** — line length between roughly 45 and 80 characters for body. Real
   weight and size contrast between levels. No orphans in headings. Display type
   with negative tracking.
6. **Color** — is the accent doing one job, or is it sprayed everywhere? Are
   neutrals tinted or dead grey? Is anything relying on color alone?
7. **Density** — does the page breathe at 1440 and stay usable at 390? Check the
   mobile shot specifically for cramped padding and truncated labels.
8. **Detail** — concentric radii, optical centering, elevation via shadow not
   fake borders, hit areas, icon stroke weight. See [polish.md](polish.md).
9. **States** — screenshot hover/focus/empty/loading/error too, not just the
   happy path. Use `--selector` to shoot a single component in each state.

## Slop detector

Run this against every screenshot and report matches explicitly:

- [ ] Purple/indigo gradient as the brand device
- [ ] Whole page centered
- [ ] One radius on every surface
- [ ] Inter or a default system stack as the display face
- [ ] Emoji used as icons
- [ ] Blurred blobs behind glassy cards
- [ ] Three icon-title-two-lines feature cards in a row
- [ ] `#0a0a0a` + `#fafafa` + violet dark mode
- [ ] "Seamlessly / Effortlessly / Supercharge / Built for teams" copy
- [ ] Flat uniform spacing with no compression or large jumps

Each match is a HIGH finding unless listed in the Anti-slop exceptions section of
`DESIGN.md`.

## Scorecard

Score each dimension 1-5. Anything at 3 or below needs a concrete fix, not a note.

| Dimension | 1 | 5 |
| --- | --- | --- |
| Direction legibility | Could be any product | Unmistakably this project |
| Hierarchy | Flat, everything equal | Clear first/second/third read |
| Rhythm | One uniform gap everywhere | Deliberate compression and openness |
| Type | Default scale, no contrast | Considered pairing, real contrast |
| Color discipline | Accent everywhere, dead greys | One accent with a job, tinted neutrals |
| Detail | Mismatched radii, fake depth | Concentric, optically aligned, layered |
| Responsive | Breaks or cramps at 390 | Reconsidered per breakpoint |
| Accessibility | Contrast or focus failures | Clean axe pass, visible focus, keyboard order |

## Report format

State the mode (`quick` = HIGH/MEDIUM only, cap 5 findings; `full` = cap 15),
the exact screenshots inspected, and the scorecard. Then:

| Severity | Location | Before | After | Why |
| --- | --- | --- | --- | --- |

- **HIGH** — breaks the direction, blocks a task, fails accessibility, or is a
  slop-detector match.
- **MEDIUM** — noticeable inconsistency or usability friction.
- **LOW** — isolated polish; `full` mode only.

Cite `path/to/file:line`. Consolidate a systemic issue into one row listing every
affected location. Never pad to reach the cap.

Then a **Considered but rejected** section (2-5 real candidates and why they
lost), a **Verification** section listing the exact commands run and what you
observed, and a **Verdict**:

- `Block` — any HIGH finding remains.
- `Needs changes` — only MEDIUM/LOW remain.
- `Approve` — no actionable findings, and the direction is legible in the pixels.

Label any check you did not run as **Not verified** and say what remains. Never
imply you inspected a surface you did not screenshot.
