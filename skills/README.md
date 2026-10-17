# Skills

[Agent Skills](https://agentskills.io/specification) that Mission Centre installs on launch into
`~/.claude/skills` (Claude Code) and `~/.agents/skills` (pi and others). It only fills gaps: a skill
you already have is never overwritten, and drift shows up under [H] Health / [G].

| Skill | What | Licence |
|---|---|---|
| [`vibe-check`](vibe-check/SKILL.md) | Turns a beginner's app idea into a buildable plan, and keeps them oriented while building. Used by `[NA] New App`. Vendored from [TexasBedouin/vibe-check](https://github.com/TexasBedouin/vibe-check) (see `VENDORED.md`). | MIT, see `vibe-check/LICENSE` |
| [`ui-design`](ui-design/SKILL.md) | Art direction and visual review for web UIs in any stack: direction, tokens, build, screenshot review. | Includes MIT material, see `ui-design/references/sources.md` |

## Without Mission Centre

Copy a skill folder into the agent's skills folder:

```bash
cp -R skills/ui-design ~/.agents/skills/        # pi and others
cp -R skills/ui-design ~/.claude/skills/        # Claude Code
```

## ui-design screenshot and audit scripts

`ui-design/scripts/shoot.mjs` and `audit.mjs` use Playwright and axe-core. Install them once, one
folder **above** the skill, so Node finds them and the skill folder itself stays unchanged:

```bash
npm install --prefix ~/.agents/skills playwright@1.62.1 @axe-core/playwright@4.11.2
npx --prefix ~/.agents/skills playwright install chromium
```
