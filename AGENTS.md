# OpsKamer: notes for contributors and coding agents

OpsKamer = Mission Centre (a cross-platform PowerShell TUI launcher that opens your projects in Claude Code or pi) + a pi
setup + bundled skills + docs. Read [README.md](README.md) first, then [docs/LESSONS.md](docs/LESSONS.md):
most rules below come from a bug.

## Stack

- PowerShell 5.1+ on Windows, PowerShell 7+ on macOS/Linux. No build step, no modules, no dependencies.
- Bash only for `launch.sh` and `pi/scripts/bootstrap.sh`.

## Layout

| Path | What |
|---|---|
| `Mission-Centre.ps1` | Entry point: constants, config globals, library loader, `Start-MissionCentre` |
| `lib/NN-*.ps1` | Functions, **dot-sourced** in filename order (see below) |
| `launch.sh` / `launch.bat` | Launchers |
| `setup.ps1` | One-time, re-runnable device setup (Windows + macOS) |
| `jig-profiles/` | Starter Jig profiles (Claude Code model aliases, never dated ids) |
| `skills/` | Bundled skills, installed to `~/.claude/skills` and `~/.agents/skills` |
| `pi/` | pi bootstrap scripts and config |
| `tests/run-tests.ps1` | Dependency-free, hermetic test suite |
| `tools/privacy-check.ps1` | Fails on secrets, private IPs, personal paths/emails, non-noreply commits |
| `docs/` | Mission Centre manual, model access, lessons |

`config.json`, `projects.json` and `.mission-centre/` are per user and gitignored. Never commit them.

## Module layout

`Mission-Centre.ps1` defines script-scoped config globals (`$ScanRoot`, `$Pi*`, `$ToolUpdate*`, marker
arrays, ...) and then dot-sources `lib/*.ps1`. **Dot-sourcing, not `Import-Module`, is required** so the
globals stay visible inside the functions. To add a function, put it in the matching `lib/NN-*.ps1`.

- `00-config` first-run config · `05-vibe` banner, theme, animations · `10-util` quoting and command
  builders · `20-ui` menus · `30-discovery` project discovery, registry I/O, scaffolding, skills install ·
  `35-sharedstate` self-update and the optional shared registry · `40-sessions` Claude Code / pi session
  history · `50-context` CLAUDE.md setup, wiki config, context pack · `60-health` checks and Jig preflight ·
  `65-updates` toolchain and pi-fork updates · `66-sources` skills, pi packages and tokenjuice from their own sources · `80-launch` terminals and every launch path ·
  `99-main` menu loop and dispatch.

## Rules

- **Run the tests on both editions** before a pull request:
  `powershell -NoProfile -ExecutionPolicy Bypass -File tests\run-tests.ps1` and
  `pwsh -NoProfile -File tests/run-tests.ps1`. CI runs both on Windows, plus PowerShell 7 on macOS and
  PSScriptAnalyzer.
- **Tests stay hermetic:** fixtures in a temp folder only; never the real `~/.claude`, `~/.pi`, `~/.jig`,
  config or registry. Stub with functions that shadow cmdlets or CLIs.
- **Never block a launch** on a network call, an update or an optional feature. Best effort, warn, continue.
- **Never destroy user state:** back up before changing a file (`*.bak-<timestamp>`), fast-forward only,
  never `reset`/`clean`, never stop processes the launcher did not start.
- **No keys, no personal data.** Run `pwsh -NoProfile -File tools/privacy-check.ps1`. Enable the pre-push
  hook once per clone: `git config core.hooksPath tools/hooks`.
- **Model access is the user's own.** Do not add code that reuses a subscription login outside the app it
  was issued for. See [docs/MODEL-ACCESS.md](docs/MODEL-ACCESS.md).
- **Licences:** vendored third-party files keep their licence file and a `VENDORED.md`; list them in
  [THIRD-PARTY.md](THIRD-PARTY.md). Prefer linking over vendoring.
