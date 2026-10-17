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

## Updates come from upstream

Mission Centre updates this skill **from its source**, not from this repo. `source.json` names the
upstream repo, branch, the files above and the licence. Once a day (or on `[U]`) Mission Centre compares
the upstream branch with the commit it last installed. When upstream has moved, it stages the new files in
`.mission-centre/skill-sources/vibe-check/` and installs them into `~/.claude/skills` and
`~/.agents/skills`. It does not overwrite a copy you changed, and it refuses the update if the upstream
licence is no longer MIT.

The pinned commit above is only the starting point that ships with OpsKamer.
