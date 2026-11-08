---
title: "How this second brain works"
summary: "Rules of this vault for you and for AI agents: folders, note format, deposit and question workflows."
type: note
tags: [meta]
---

# How this second brain works

This vault is a **second brain**: everything worth keeping goes in, and you (or an AI agent) can dig it up or
ask questions about it later. It is plain Markdown, so Obsidian, any text editor and any AI agent can read it.

**AI agents:** this file is the rulebook for this vault. Follow it together with the `second-brain` skill;
where they differ, this file wins. You may edit this file to change the rules.

## Folders

| Folder | What goes in |
|---|---|
| `_inbox/` | Quick captures that are not filed yet. Drop anything here. |
| `_attachments/` | Original files: PDFs, images, audio. |
| `notes/` | One idea, fact, how-to, recipe or decision per note. |
| `sources/` | One note per article, book, video, podcast or document. |
| `people/` | One note per person. |
| `projects/` | One note per project: goal, status, decisions, next steps. |
| `journal/` | Daily notes, `YYYY-MM-DD.md`. |
| `answers/` | Answers to questions that were worth keeping. |
| `_archive/` | Processed captures and retired notes. Nothing is deleted. |
| `_templates/` | Templates for Obsidian's Templates plugin. |

## Note format

Every note starts with frontmatter. `title` and `summary` are required; `summary` is one line.

```markdown
---
title: "Note title"
summary: "One line that says what is in this note."
type: note
tags: [topic]
created: 2026-01-01
updated: 2026-01-01
source: "conversation"
---
```

Link related notes with `[[Note title]]` under a `## Related` heading.

## Ground rules

- Never delete anything: move it to `_archive/`.
- No passwords, PINs, card or ID numbers, or API keys in this vault.
- `log.md` records every deposit, newest at the bottom.
