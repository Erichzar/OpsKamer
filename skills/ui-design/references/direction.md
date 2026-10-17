# Phase 1 — Direction

Goal: produce a written, specific, per-project `DESIGN.md` that a stranger could
build from and recognise. Generic direction produces generic interfaces; this
phase is where the entire outcome is decided.

You are not choosing the direction alone. Your job is to make the choice
*legible and cheap* for the human, then write it down.

## Gather

Ask for what is missing. Do not proceed on assumptions; a wrong assumption here
is paid for in every screen.

1. **Subject** — what is the product, concretely? Not "a SaaS dashboard" but
   "a scheduling tool for tattoo studios".
2. **Audience** — who uses it, in what context, on what device, how often?
3. **The single job** — what must this page or screen accomplish? One sentence.
4. **References** — ask for 2-5 sites, screenshots, or images they like. Ask
   what specifically they like about each. Also ask for one they hate.
5. **Anti-references** — who must this NOT look like? Usually a direct
   competitor or the current version.
6. **Constraints** — existing brand assets, locked colors, required fonts,
   dark mode, i18n, target browsers, performance budget, accessibility level.

If the human supplies reference images, `read` each one and extract, in writing:
palette (approximate hexes), type treatment (serif/sans/mono, weight contrast,
scale range), layout structure (grid, density, asymmetry), motion character, and
the one device that makes it distinctive. Then state explicitly what you will
borrow and what you will deliberately not borrow. Never copy a reference wholesale.

## Propose

When direction is not already pinned, present **three genuinely different**
options. Not three shades of the same minimal sans-serif layout — three
different worldviews. Each option gets:

- A **named style** drawn from a real vocabulary (see
  [style-vocabulary.md](style-vocabulary.md)). "Swiss editorial" is a direction;
  "modern and clean" is not.
- A **palette**: 5-7 concrete hex values with roles (surface, ink, accent,
  support, edge). Include the reasoning for the accent.
- A **type pairing**: display face + body face by name, with a fallback stack
  and where each is used. Weight and scale range.
- A **structural device**: the thing that makes layout mean something —
  numbered sections, a persistent sidebar rail, a hard grid rule, an
  asymmetric split, oversized type as furniture.
- The **hero thesis**: what the top of the page does. It should be the most
  characteristic thing in the subject's world, not a headline with a gradient
  and three stats.
- **One risk**: a single deliberate, defensible choice that a cautious designer
  would not make. Say what it is and why it is worth it.

Keep each option to about six lines. The human is picking a direction, not
reading a deck.

## Ground it in the subject

Distinctive choices come from the subject's own world — its materials,
instruments, artifacts, and vernacular. A tattoo scheduler can borrow from flash
sheets and stencil linework. A bond-trading tool can borrow from ticker tape and
tabular density. Look there before reaching for whatever is fashionable.

If the human has stated preferences before, or you know their existing brand,
weight that above novelty.

## Write

Copy [../assets/DESIGN.template.md](../assets/DESIGN.template.md) to the project
(project root, or `docs/DESIGN.md` if the root is crowded) and fill in every
section. Empty sections are failures — if something is genuinely undecided,
write "undecided, defaulting to X until told otherwise" so the default is visible.

Rules for `DESIGN.md`:

- Every color is a hex with a named role. No "a nice blue".
- Every font is a real family name with a real fallback stack and a license note
  (Google Fonts, self-hosted, licensed, system).
- The type scale is a list of concrete sizes and line-heights, not "responsive".
- Include a **Rejected** section: directions considered and why they lost. This
  stops the next session relitigating settled decisions.
- Include an **Anti-slop exceptions** section listing any forbidden pattern from
  `SKILL.md` that this direction deliberately uses, and the justification.

## Confirm

Present `DESIGN.md` and stop. Do not start Phase 2 until the human accepts it or
amends it. This is the one place the human must be in the loop.
