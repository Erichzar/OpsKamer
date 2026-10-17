# Model access

OpsKamer launches coding agents. It does not provide models, keys, accounts or a proxy. Each agent needs
its own access, set up by you and under your provider's terms.

## Claude Code (the default engine)

Claude Code signs in with your Claude account (Pro, Max, Team or Enterprise) or an Anthropic Console API
key. Mission Centre's Claude launches (`[L]`, `[C]`, `[R]` by default) start Claude Code itself, so they use
that login exactly as Anthropic intends. Keep Claude Code current (`claude update`, or let Mission Centre
check it): Anthropic only serves new models to recent Claude Code versions.

## pi

pi talks to model providers directly. **Already have pi working?** Then there is nothing to do: Mission
Centre leaves `pi.provider` and `pi.model` empty by default and runs pi with your own
`~/.pi/agent/settings.json`, and the bootstrap keeps your existing pi config.

Setting it up fresh, pick one:

1. **An API key** (simplest). For Anthropic, create a key in the
   [Anthropic Console](https://console.anthropic.com/) and set it in your shell:

   ```bash
   export ANTHROPIC_API_KEY="<your key>"        # macOS/Linux: add to ~/.zshrc or ~/.bashrc
   ```

   ```powershell
   setx ANTHROPIC_API_KEY "<your key>"          # Windows: new terminals pick it up
   ```

   pi supports many other providers (OpenAI, Google, OpenRouter and more). See
   [pi's documentation](https://github.com/earendil-works/pi) for their variables. Set the default in pi's
   own settings, or only for Mission Centre with `setup.ps1 -Provider <p> -Model <m>`.

2. **A local model server** (no key, no cost per token, needs a capable machine). Run
   [Ollama](https://ollama.com) or [LM Studio](https://lmstudio.ai), add the server to
   `~/.pi/agent/models.json` (see `pi/pi-config/models.local-example.json`), and set `pi.provider` to its
   name. Set `pi.healthUrl` (Ollama: `http://localhost:11434/`) and Mission Centre checks the server before
   each pi launch, and can start it (`pi.startCommand`, or a Windows Scheduled Task in `pi.taskName`).

Check that it works: `pi -p "Reply with exactly: PI OK"`.

## Why there is no subscription bridge

The setup OpsKamer comes from once ran pi through a local proxy that reused a Claude subscription login.
It is **not** included here, and we don't recommend building one:

- Anthropic's [Consumer Terms](https://www.anthropic.com/legal/consumer-terms) and Claude Code's legal and
  compliance notes allow a Claude Free, Pro or Max login (OAuth) only in Claude Code and claude.ai. Using
  that login in any other tool, pi included, is not permitted.
- If you want Claude models in pi, use an API key, which is what the terms provide for.
- If you set up some other route to a model (a team gateway, a hosted proxy, another provider), that's your
  own setup: check that it fits the provider's terms, keep its keys out of this repo, and point
  `pi.provider` at it.

## Keys and this repo

- Never commit keys. `.gitignore` already excludes `.env`, `auth.json` and `*.credentials*` files.
- `pi/scripts/bootstrap.*` never reads or writes your keys, `auth.json` or `models.json`.
- `setup.ps1` only checks whether a key **exists** (environment variable or pi's auth file); it never
  reads its value.
