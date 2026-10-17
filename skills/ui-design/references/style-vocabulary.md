# Style Vocabulary

A direction needs a name. Naming forces commitment and gives the human something
to accept or reject. Use these as starting points, combine them, or name a new
one — but never ship "modern and clean".

Each entry: what it is, what it demands, and where it fails.

## Structural / typographic

**Swiss editorial** — Hard grid, Helvetica/Neue Haas or Univers, heavy use of
whitespace and rule lines, flush-left ragged-right, no decoration. Demands
disciplined spacing and real content hierarchy. Fails when content is thin — the
grid exposes emptiness.

**Editorial magazine** — Large serif display, drop caps, pull quotes, multi-column
text, images bleeding to the edge. Demands actual writing. Fails on dense app UI.

**Brutalist web** — Exposed structure, system fonts, visible borders, raw links,
high contrast, deliberate ugliness as honesty. Demands confidence and good
information architecture. Fails when the product needs to feel trustworthy or
premium.

**Terminal / monospace** — Monospaced everything, grid of characters, ASCII rules,
green/amber or paper-white, block cursors. Demands restraint in color. Fails for
non-technical audiences.

**Data-dense / Bloomberg** — Tabular numbers, tight rows, thin dividers, color used
only for state, information over air. Demands genuinely dense data. Fails on
marketing pages.

## Period / cultural

**Googie / atomic age** — Boomerang and starburst forms, angled type, turquoise,
coral, cream, chrome. Demands commitment to the whole world. Fails when applied
as decoration on a modern layout.

**Mid-century modern** — Muted warm palette, geometric shapes, Futura/Avenir,
generous margins, print-poster composition.

**Bauhaus / constructivist** — Primary colors, hard geometry, diagonal type,
black rules, circles and triangles as structure.

**Y2K / frutiger aero** — Gloss, gradients on chrome, aqua, lens flare, bubble
forms. High risk, very legible as a choice.

**Zine / photocopy** — Halftone, misregistration, cut-paper collage, marker
annotation, stapled feel.

**Blueprint / technical drawing** — Cyan lines on dark, dimension arrows,
annotation callouts, monospaced labels, isometric diagrams.

## Material / tactile

**Paper and ink** — Off-white stock, letterpress depth, ink-bleed serif, deckled
edges, minimal color. Warmth without nostalgia.

**Risograph** — Two or three flat spot colors, overprint multiply, visible
registration offset, grain.

**Physical instrument** — Skeuomorphic borrowing from a real device relevant to
the subject: a mixing desk, a darkroom timer, a field notebook, a card catalog.
Only works when the device relates to the product.

**Soft depth** — Layered shadows, warm neutrals, rounded but varied radii, gentle
motion. The tasteful default; needs a strong accent or it drifts toward slop.

## Contemporary

**Neo-grotesque product** — Inter-adjacent sans done well: real weight contrast,
tight tracking on display, generous body line-height, one saturated accent, near-
neutral greys with a deliberate temperature. Only escapes slop with a strong
structural device and a non-default accent.

**High-contrast editorial dark** — True black or deep tinted dark, one bright
accent, oversized display serif or condensed sans, photographic hero.

**Utilitarian / civic** — GOV.UK lineage: plain, legible, high-contrast, focused
on task completion, no ornament. Signals competence and accessibility.

## Font pairing starting points

Pairings that are not the default. Check licensing before committing.

| Display | Body | Reads as |
| --- | --- | --- |
| GT Sectra / Newsreader | Inter Tight / IBM Plex Sans | Editorial, credible |
| Söhne / Neue Haas Grotesk | Söhne, lighter weight | Swiss product |
| Instrument Serif | Geist Mono | Modern editorial with a technical edge |
| Fraunces (high softness/wonk) | Public Sans | Warm, characterful, not twee |
| Space Grotesk | Space Mono | Technical, slightly retro-future |
| Bricolage Grotesque | Literata | Contemporary print |
| Redaction | Karla | Rough, printed, human |
| Playfair Display | Source Sans 3 | Classical, safe |
| Archivo Expanded | Archivo Narrow | Poster-like, strong scale contrast |
| IBM Plex Serif | IBM Plex Sans Condensed | Institutional, technical |
| Libre Caslon Display | Libre Franklin | American editorial |
| Departure Mono / Berkeley Mono | Inter | Terminal-adjacent product |

Rules: pair across categories or across widths, never two similar sans faces.
Set a real scale contrast — if display and body sit within 1.5x of each other at
their largest, the pairing is doing nothing. One face used at many weights beats
two faces used at one weight each.

## Palette construction

- Pick **one** accent that carries meaning for the subject and use it sparingly;
  a second accent needs a reason (state, category, data series).
- Neutrals need a temperature. Pure `#808080` greys read as unfinished. Tint the
  neutral ramp toward the accent's complement or toward the paper color.
- Reserve the highest-contrast pair for text, not for decoration.
- Define semantic roles before shades: surface, raised surface, ink, muted ink,
  edge, accent, accent ink, positive, caution, negative.
- Test the palette at 320px on a phone in daylight, not just on your monitor.
