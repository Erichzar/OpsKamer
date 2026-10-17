# Phase 3 — Build and polish

Implement against tokens only. If you are typing a raw hex, px value, or timing
into a component, either a token is missing or you are drifting from the system.

Before writing a fix, identify the project's existing styling system and express
the change in that system. Never introduce a second styling system to apply a
polish fix.

## The details that decide whether it feels finished

Condensed from *Details that make interfaces feel better* (MIT, Jakub Krehel).
Full detail lives in the vendored references — load the one you need, not all of them.

| Area | Reference |
| --- | --- |
| Text wrapping, font smoothing, tabular numbers | [typography.md](typography.md) |
| Radius, optical alignment, shadows, image outlines, hit areas | [surfaces.md](surfaces.md) |
| Interruptible motion, enter/exit, icon animation, press feedback, restraint | [animations.md](animations.md) |
| Stroke weight, `currentColor` states, outline vs fill, sizing, RTL | [icons.md](icons.md) |
| Transition specificity, `will-change` | [performance.md](performance.md) |

### Non-negotiables

1. **Concentric radius** — outer radius = inner radius + padding. Mismatched
   nested radii is the single most common thing that makes UI feel off.
2. **Optical over geometric alignment** — icons in buttons, play triangles, and
   asymmetric glyphs need manual nudging even when the box is centered.
3. **Shadows for elevation, borders for structure** — a border used only to fake
   depth should be layered transparent `box-shadow` instead. Keep borders that
   carry structure or state.
4. **Interruptible animations** — CSS transitions for interactive state changes;
   keyframes only for staged sequences that run once.
5. **Stagger enters, soften exits** — ~100ms stagger for infrequent staged
   entrances only; exits use a small fixed `translateY` and are gentler than
   enters. `ease-out` for both.
6. **Never `transition: all`** — name the exact properties.
7. **Tabular numbers** for anything that updates, so layout does not shift.
8. **`text-wrap: balance`** on headings, **`pretty`** on body.
9. **Scale `0.96` on press**, never below `0.95`.
10. **Hit areas** 44x44px for touch, at least 40x40px in dense desktop UI; extend
    with a pseudo-element rather than inflating the visible control. Never let
    two hit areas overlap.
11. **Icon stroke matches text weight** — 1.5px beside 400, 2px beside 600. One
    icon set per surface.
12. **One SVG recolored per state** via `currentColor`; outline default, fill for
    active.
13. **Motion restraint** — no custom animation on high-frequency interactions,
    and motion is never the only feedback channel.
14. **Image outlines** — 1px at ~10% opacity, pure black in light mode, pure
    white in dark. A tinted outline reads as dirt on the edge.
15. **`will-change` sparingly** — only `transform`, `opacity`, `filter`, and only
    when you observe first-frame stutter.

### Build-order that avoids rework

1. Tokens and the proof page (Phase 2 deliverable).
2. Primitives: button, input, link, card, table row — every state, in isolation.
3. One real screen end to end, including empty, loading, and error states.
4. Screenshot it (Phase 4) before building screens two through ten.

Building ten screens against an unreviewed primitive set means fixing the same
mistake ten times.

### States are not optional

For every interactive element: default, hover, focus-visible, active, disabled,
loading. For every data surface: empty, loading, partial, error, and the
"too much data" case. A screen that only exists in its happy state is unfinished,
not designed.
