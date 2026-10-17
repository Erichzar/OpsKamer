# Vendored skill: vibe-check

This directory is a **vendored copy** of the third-party `vibe-check` Claude Code
skill, bundled so Mission Centre can install it for the `[NA] New App` path and the
`vibe` Jig profile without a network round-trip.

| Field | Value |
|-------|-------|
| Source | https://github.com/TexasBedouin/vibe-check |
| Upstream branch | `master` |
| Pinned commit | `f81d7496e2387cf47dc26aa293f54382f6c9bff6` |
| Version | 1.8.0 (see `VERSION`) |
| License | MIT (see `LICENSE`) |

## What was vendored

`SKILL.md`, `references/`, `LICENSE`, `VERSION`. The upstream `examples/`
(large self-contained HTML blueprints) and repo tooling (`bump.sh`, `CHANGELOG.md`,
`README.md`, `RELEASING.md`) are intentionally **not** vendored — they are not needed
at skill runtime.

## Refreshing

To pull a newer upstream release, re-run from the repo root:

```bash
npx skills add TexasBedouin/vibe-check   # or: git clone + copy SKILL.md, references/, LICENSE, VERSION
```

Then update the pinned commit and version above.
