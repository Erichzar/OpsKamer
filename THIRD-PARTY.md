# Third-party material

OpsKamer is Apache-2.0 (see [LICENSE](LICENSE)). The parts below come from others and keep their own terms.

## Included in this repository

| What | Where | Source | Licence |
|---|---|---|---|
| vibe-check skill | `skills/vibe-check/` | [TexasBedouin/vibe-check](https://github.com/TexasBedouin/vibe-check); starting commit in `source.json`, then updated from upstream (licence checked on every update) | MIT, `skills/vibe-check/LICENSE` |
| *Details that make interfaces feel better* | `skills/ui-design/references/` (typography, surfaces, animations, icons, performance) | [jakubkrehel/make-interfaces-feel-better](https://github.com/jakubkrehel/make-interfaces-feel-better), Jakub Krehel | MIT, `skills/ui-design/references/LICENSE-make-interfaces-feel-better.txt` |
| Ideas adapted (not copied) in `ui-design` | `skills/ui-design/` | [anthropics/skills](https://github.com/anthropics/skills) (`frontend-design`, `web-artifacts-builder`, `webapp-testing`) | see that repository; attribution in `skills/ui-design/references/sources.md` |

## Installed or used, not included

These are downloaded by you or by the scripts from their own sources, under their own licences.

| What | Used for | Source |
|---|---|---|
| pi (`@earendil-works/pi-coding-agent`) | the pi agent | [earendil-works/pi](https://github.com/earendil-works/pi), MIT |
| pi fork (optional) | `pii`, from source | default [leo-labs-ai/pi-mono](https://github.com/leo-labs-ai/pi-mono); any fork you choose |
| pi-semantic-grep (`@howaboua/pi-semantic-grep`) | pi package in `settings.json` | [npm](https://www.npmjs.com/package/@howaboua/pi-semantic-grep), MIT |
| tokenjuice (optional) | compacts command output for pi | [vincentkoc/tokenjuice](https://github.com/vincentkoc/tokenjuice), MIT |
| Playwright, axe-core (optional) | `ui-design` screenshot and audit scripts | [Playwright](https://github.com/microsoft/playwright) (Apache-2.0), [axe-core](https://github.com/dequelabs/axe-core) (MPL-2.0) |
| Claude Code | the Claude engine | [Anthropic](https://docs.anthropic.com/en/docs/claude-code), Anthropic's terms |
| Jig, Forge (optional) | Claude Code launch profiles, mission planning | [jdforsythe/jig](https://github.com/jdforsythe/jig), [jdforsythe/forge](https://github.com/jdforsythe/forge) |
| obsidian-wiki skills (optional) | wiki vault access | [Ar9av/obsidian-wiki](https://github.com/Ar9av/obsidian-wiki) |
| ai-codex (optional) | codebase index (`contextIndex`) | run with `npx ai-codex` |
