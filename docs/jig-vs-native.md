# Jig vs Native Claude Code — Trade-offs

*Decision doc, 2026-07-06. Written after a full integration audit (jig 0.1.0, claude 2.1.201).*

## Question

Mission Centre launches every project through `jig run <profile>`. Claude Code
has since grown native support for much of what a Jig profile encodes. Should
Mission Centre keep Jig as its launch backbone, or migrate to launching
`claude` directly?

## What a Jig profile does, and what's now native

| Profile key | What jig does with it | Native equivalent today |
|---|---|---|
| `model`, `effort`, `permission_mode` | pass-through flags | `--model`, `--effort`, `--permission-mode` — full parity |
| `append_system_prompt` | `--append-system-prompt` | same flag; also `CLAUDE.md` / output styles |
| `allowed_tools` / `disallowed_tools` | `--allowedTools` / `--disallowedTools` | same flags |
| `mcp_servers`, `settings` | generated settings file | `.mcp.json`, `settings.json` |
| `skills:`/`agents:`/`commands:` path lists | symlinked plugin dir | `~/.claude/skills`, `.claude/agents`, plugins — **and Mission Centre's bundled profiles never use these keys** |
| `enabled_plugins` | **disables every globally-installed plugin, re-enables only the profile's set** | no cheap native equivalent — plugins are global/per-project |
| `extends` + named profiles | one-keystroke switchable launch bundles | no native "launch profile" concept — you'd hand-assemble flags or juggle settings files |

Verified: every flag jig 0.1.0 emits exists in claude 2.1.201. The integration
mechanics are current and correct.

## Jig's two real differentiators

1. **Named, inheritable launch profiles.** `standard` / `build` / `review` /
   `vibe` as one-keystroke units of model+effort+permissions+prompt+plugins.
   Native Claude Code has nothing equivalent; replicating it means Mission
   Centre maintaining its own profile→flags mapping (which is a worse,
   less-tested reimplementation of jig).
2. **Per-profile plugin isolation.** A `review` session gets *only* the Forge
   plugin; a `standard` session gets none. Natively, enabled plugins load in
   every session — with several plugins installed this costs context tokens
   and invites trigger collisions in sessions that don't need them.

## Costs of keeping Jig

- **Version-lag risk:** jig is v0.1.0, last upstream commit 2026-04-02, and
  officially supports macOS/Linux only (works on Windows today because the
  bundled profiles avoid the `os.Symlink` code path). If a future Claude Code
  release renames a flag jig emits, launches break until jig updates.
  *Mitigation:* `Invoke-ProfilePreflight` dry-runs before launching and
  `[H]` Health runs `jig doctor` — breakage is loud, not silent.
- **A second config surface** (`~/.jig/profiles`) that can drift from the
  bundled copies. *Mitigation:* `[G]`/`[H]` now detect drift.

## Costs of migrating to native

- Reimplement profile semantics (mapping, inheritance, validation) inside
  Mission Centre PowerShell — new code, new tests, new bugs.
- Lose plugin isolation entirely, or reimplement it by generating per-launch
  `--settings` files with `enabledPlugins` maps (exactly what jig already does).
- Migration touches every launch path (`Start-WithProfile`, meta missions,
  New App, resume paths) for zero new user-facing capability.

## Recommendation

**Keep Jig.** Both of its differentiators are load-bearing for Mission Centre's
UX, the CLI compatibility is verified current, and the failure mode (flag
drift) is caught by preflight rather than silent. Revisit if either happens:

1. Claude Code ships a native launch-profile concept, or
2. jig upstream goes dead *and* a Claude Code release actually breaks a flag
   it emits.

Cheap insurance in the meantime: keep `[H]` Health green (it now checks
profile drift, plugin-cache drift, and runs `jig doctor` + `claude doctor`).
