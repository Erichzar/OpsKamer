# pi setup

[pi](https://github.com/earendil-works/pi) is a terminal coding agent (MIT). This folder installs it
with a small, sensible config. Mission Centre can then launch it per project, next to Claude Code.

```bash
./pi/scripts/bootstrap.sh              # macOS / Linux
.\pi\scripts\bootstrap.ps1             # Windows (PowerShell)
```

What it does:

1. Checks Node.js (22.19 or newer) and installs pi globally with npm if it is missing.
2. Copies `pi-config/settings.json` and `pi-config/semantic-grep.json` into `~/.pi/agent/` **only where
   you have none yet**. An existing pi setup (your provider, models, settings) is kept as it is;
   `--force` / `-Force` replaces it, after a backup (`*.bak-<timestamp>`). Re-running is safe.
3. Offers to install [tokenjuice](https://github.com/vincentkoc/tokenjuice) (MIT) for pi, through
   its own installer. It compacts long command output before the model sees it.

It does **not** touch keys or `models.json`. Model access is yours to set up: see
[../docs/MODEL-ACCESS.md](../docs/MODEL-ACCESS.md).

## The config

| File | What |
|---|---|
| `settings.json` | Default provider `anthropic`, model `claude-sonnet-5`, thinking `high`, the [pi-semantic-grep](https://www.npmjs.com/package/@howaboua/pi-semantic-grep) package (MIT), and compaction at 200k tokens. |
| `semantic-grep.json` | Settings for pi-semantic-grep. It uses a local embeddings server (LM Studio on port 1234 here). Auto-indexing is off, so nothing runs until you ask. |
| `models.local-example.json` | **Example only.** Shows how to add a local model server (Ollama) to pi. Merge the provider into your own `~/.pi/agent/models.json`. |

## Running pi from source (optional)

You can run a pi fork built from git (as `pii`) next to the npm install. `setup.ps1 -WithFork` at the
repo root clones one (by default the public [leo-labs-ai/pi-mono](https://github.com/leo-labs-ai/pi-mono)),
writes the `pii` launcher, and Mission Centre keeps it merged and rebuilt. The npm `pi` remains the
fallback when a build fails.
