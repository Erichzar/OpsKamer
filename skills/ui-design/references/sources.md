# Sources and attribution

## Vendored

**Details that make interfaces feel better** — Jakub Krehel, MIT.
<https://github.com/jakubkrehel/make-interfaces-feel-better>
Vendored verbatim as `typography.md`, `surfaces.md`, `animations.md`, `icons.md`,
`performance.md`. License text in `LICENSE-make-interfaces-feel-better.txt`.
Condensed into `polish.md`.

## Adapted

**Anthropic Agent Skills** — <https://github.com/anthropics/skills>
- `frontend-design`: the "design lead at a small studio" framing, hero-as-thesis,
  deliberate type pairing, structure-encodes-meaning, and taking one justified
  aesthetic risk. Adapted into `direction.md`.
- `web-artifacts-builder`: the explicit anti-slop list (excessive centered
  layouts, purple gradients, uniform rounded corners, Inter). Extended in
  `../SKILL.md`.
- `webapp-testing`: the Playwright reconnaissance-then-action loop. Reimplemented
  in Node in `../scripts/shoot.mjs` because this toolchain has no Python
  dependency and the pi fork has no MCP client.

## Not vendored, worth mining

Large, opinionated, or fast-moving. Read before borrowing; do not depend on them.

| Project | Why look |
| --- | --- |
| <https://github.com/Leonxlnx/taste-skill> | Broad anti-slop skill set, many style variants |
| <https://github.com/bitjaru/styleseed> | Design-method engine, skins, judgment rubrics |
| <https://github.com/plugin87/ux-ui-agent-skills> | DTCG tokens, WCAG 2.2 checklists, 138 design systems |
| <https://github.com/dominikmartn/hue> | Learns a brand and derives a full system |
| <https://github.com/dominikmartn/nothing-design-skill> | A single strong design language, well executed |
| <https://github.com/JimLiu/baoyu-design> | Polished output, style presets |

## External tools (hosted, optional)

Not dependencies. Useful as a second opinion after Phase 4.

- **impeccable.style** — design vocabulary and slop-stripping commands for agents.
- **Google Stitch** (`stitch.withgoogle.com`) — generates fresh design themes.
  Do not feed it the existing URL if you want a genuinely new direction.

## Provenance note

The framing of this skill — that the human is the art director, that direction
must be written into a markdown design system the agent references, and that
quality comes from iteration rather than a one-shot prompt — comes from the
r/ClaudeAI community consensus on building sites with Claude, plus the sources
above.
