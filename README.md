# OpsKamer

**A working setup for AI-assisted coding on macOS and Windows**: a project launcher that keeps your tools
current, a pi coding-agent setup, a few skills, and the lessons learned building it.

*Kamer* is Afrikaans and Dutch for *room*: this is the ops room you start every coding session from.

| Part | What it gives you |
|---|---|
| [**Mission Centre**](docs/MISSION-CENTRE.md) | A terminal menu over all your projects. Shows recent sessions, launches Claude Code (through [Jig](https://github.com/jdforsythe/jig) profiles) or [pi](https://github.com/earendil-works/pi) in the right folder, plans new work with Forge or vibe-check, and keeps itself, Claude Code, pi and an optional pi fork up to date. |
| [**pi setup**](pi/README.md) | Installs pi with a sensible config. Optional: run a pi fork from source as `pii`. |
| [**Skills**](skills/README.md) | `vibe-check` (idea to buildable plan, for beginners) and `ui-design` (art direction and visual review). |
| [**Lessons**](docs/LESSONS.md) | What broke, and the rules that came out of it: updates, Windows quirks, safe self-updates, tests, privacy. |

Everything runs locally in PowerShell. There is no server and no account, and nothing is sent anywhere
except what your own tools already send.

## Quick start

You need **git**, **Node.js** (22.19+), **PowerShell** (built in on Windows; on macOS
`brew install powershell`) and **[Claude Code](https://docs.anthropic.com/en/docs/claude-code)**.
Jig and the Forge plugin are optional but recommended: see [docs/MISSION-CENTRE.md](docs/MISSION-CENTRE.md).

**macOS**

```bash
git clone https://github.com/bflutz/OpsKamer ~/Tools/OpsKamer
cd ~/Tools/OpsKamer
bash launch.sh                 # first run asks for your projects folder; press Q to quit afterwards
./pi/scripts/bootstrap.sh      # optional: install pi
pwsh ./setup.ps1               # check tools, switch on the pi engine
bash launch.sh
```

**Windows** (PowerShell)

```powershell
git clone https://github.com/bflutz/OpsKamer C:\Tools\OpsKamer
cd C:\Tools\OpsKamer
.\launch.bat                   # first run asks for your projects folder; press Q to quit afterwards
.\pi\scripts\bootstrap.ps1     # optional: install pi
powershell -ExecutionPolicy Bypass -File .\setup.ps1
.\launch.bat
```

Then press `S` to scan for projects, pick one, and `L` to launch it. `H` runs a health check and `U` checks
for updates.

## Model access: bring your own

OpsKamer does not ship keys, accounts or a proxy. You choose how your agents reach a model:

- **Claude Code** uses your own Claude login (a subscription or an API key). Mission Centre's Claude
  launches use it as is.
- **pi** needs its own model access: an API key for a provider (for example `ANTHROPIC_API_KEY`), or a
  local model server such as Ollama. If pi already works on your machine, OpsKamer uses it as it is: it
  launches pi with your own settings and does not overwrite your pi config.

**There is no subscription bridge in this repo.** Anthropic's terms allow a Claude Free, Pro or Max login
only in Claude Code and claude.ai, not in other tools such as pi. If you build your own route to a model,
make sure it fits your provider's terms. Details: [docs/MODEL-ACCESS.md](docs/MODEL-ACCESS.md).

## Keeping it current

Mission Centre updates itself at launch (fast-forward only, never over your local changes). It also checks
Claude Code, pi and an optional pi fork at most once a day, and **[U]** forces a check. See
[Tool Updates](docs/MISSION-CENTRE.md#tool-updates).

## Your data stays yours

Your project list (`projects.json`), settings (`config.json`) and session history stay on your machine, and
are gitignored. The optional shared project registry for several devices lives in a git repository **you**
own (keep it private). See [Same Projects on Every Device](docs/MISSION-CENTRE.md#optional-same-projects-on-every-device).

## Contributing

Issues and pull requests are welcome. Please run the tests (`tests/run-tests.ps1`, Windows PowerShell 5.1
and PowerShell 7) and the privacy check (`tools/privacy-check.ps1`) first. See [AGENTS.md](AGENTS.md).

## Licence

Apache License 2.0, see [LICENSE](LICENSE). Third-party parts keep their own licences, see
[THIRD-PARTY.md](THIRD-PARTY.md).
