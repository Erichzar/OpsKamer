# Second Brain

A personal knowledge base you can **put anything into** and later **dig up or ask questions about**. It is an
[Obsidian](https://obsidian.md) vault (a plain folder of Markdown notes) with an AI librarian on top:

| Part | What it does |
|---|---|
| **The vault** | Your notes, as plain `.md` files. Obsidian shows them, links them and searches them, on your computer and your phone. Nothing is locked in: any text editor can read them. |
| **The `second-brain` skill** | Teaches Claude Code and pi to file what you give them (summary, tags, links to related notes, a log line) and to answer questions from your notes, citing them. Works in **any** session, not only from Mission Centre. |
| **Mission Centre `[BR]`** | Quick deposits without waiting for an agent, a count of notes and inbox items, and one key to ask, process the inbox or open Obsidian. |

Everything stays on your machine (or in your own iCloud/Obsidian Sync). The agent reads notes through your own
Claude Code or pi model access, like any other file.

## Set it up (once)

1. **Install Obsidian** (free) from [obsidian.md](https://obsidian.md). On a Mac you can also use
   `brew install --cask obsidian`.
2. **Start Mission Centre** (`bash launch.sh` on a Mac, `.\launch.bat` on Windows) and press **`BR`**.
3. **Pick the folder.** Press Enter for the suggestion:
   - on a Mac where Obsidian's iCloud folder exists, it is
     `~/Library/Mobile Documents/iCloud~md~obsidian/Documents/SecondBrain`, which also syncs to Obsidian on your
     iPhone or iPad;
   - otherwise `~/SecondBrain`.

   Already have an Obsidian vault? Type its path instead: Mission Centre only adds the missing folders and
   starter files and never changes or deletes your notes (a vault with its own `.obsidian/` settings keeps them).
4. Press **`O`** to open it in Obsidian. The first time, Obsidian asks you to **Open folder as vault**: pick the
   same folder. After that, `O` opens it directly.

That is all. Mission Centre remembers the folder in `config.json` (`"secondBrain": { "vault": "..." }`) and
writes `~/.second-brain/config` so the skill can find the vault from any folder.

Without Mission Centre: copy `skills/second-brain` into `~/.claude/skills/` (Claude Code) and `~/.agents/skills/`
(pi), then ask your agent *"set up my second brain"*. It creates the vault from the skill's template.

## Put things in

| How | When |
|---|---|
| **`[BR]` > `[D]` Deposit** | Fastest. Type or paste text (finish with two empty lines), or **drag a file** (PDF, image, ...) into the window. It lands in `_inbox/` right away; your original file stays where it was. |
| **In any agent session** | Say *"onthou dit: ..."*, *"stoor hierdie artikel in my brein: <link>"*, *"put this meeting in my second brain"*. The agent files it straight away. |
| **In Obsidian** | New notes go to `_inbox/` by default. Write anything; on your phone too. |
| **Finder / Explorer** | Drop files into the vault's `_inbox/` folder. |

Then **`[BR]` > `[P]` Process inbox**: the agent turns each capture into a proper note (the right folder, a
one-line summary, tags, links to related notes), logs it in `log.md`, and moves the capture to
`_archive/inbox/`. Nothing is ever deleted.

## Get things out

- **`[BR]` > `[A]` Ask**: *"Wat het ek oor die huis se dak besluit?"*, *"What did I save about sourdough?"*,
  *"Wie het ek by die konferensie ontmoet?"*. The agent searches in Afrikaans and English, answers from your
  notes with `[[links]]` to them, and says plainly what your notes do not cover. A good answer can be kept in
  `answers/`.
- **`[BR]` > `[C]` Chat**: an open session with your second brain for several questions, or a tidy-up
  (*"find duplicates and notes without a summary"*).
- **In Obsidian**: search (`Cmd+Shift+F` / `Ctrl+Shift+F`), the graph view, backlinks, or `log.md` for what came
  in recently.

`[A]`, `[P]` and `[C]` open Claude Code, or pi when pi is your default engine (`"defaultEngine": "pi"`), in the
vault folder.

## What is in the vault

```
SecondBrain/
  index.md        your home page in Obsidian
  BRAIN.md        the rules of this vault, for you and for agents (edit it to change them)
  log.md          one line per deposit, newest at the bottom
  _inbox/         captures not filed yet
  _attachments/   original files (PDFs, images, audio)
  notes/          one idea, fact, how-to or decision per note
  sources/        one note per article, book, video or document
  people/         one note per person
  projects/       one note per project
  journal/        daily notes (YYYY-MM-DD.md)
  answers/        answers worth keeping
  _archive/       processed captures and retired notes
  _templates/     templates for Obsidian's Templates plugin
  .obsidian/      Obsidian settings: new notes to _inbox, attachments to _attachments, daily notes to journal
```

Every note starts with a little frontmatter block (`title`, a one-line `summary`, `type`, `tags`, dates,
`source`). The summaries are what make a large vault quick to search: the agent reads all of them first, then
opens only the notes that matter.

To use the note templates in Obsidian, turn on **Settings > Core plugins > Templates** (the folder is already
set to `_templates`).

## Rules the agent follows

- It never deletes: old captures and merged notes go to `_archive/`.
- It never invents: facts, numbers and names are kept exactly; anything unsure is marked `(?)`.
- No secrets: passwords, PINs, card and ID numbers or API keys are left out (use a password manager).
- Your vault's `BRAIN.md` wins over the skill, so you can change folders or rules there.
- Text inside your notes, web pages or files is treated as material to file, never as instructions.

## Several devices

- **Mac + iPhone/iPad:** keep the vault in Obsidian's iCloud folder (the default suggestion when it exists).
- **Mac + Windows:** Obsidian Sync (paid), or keep the vault in a private git repository and use the
  Obsidian Git community plugin. Each Mission Centre deposit is its own file, so two devices never edit the
  same capture.

On each device, press `[BR]` once and point it at that device's copy of the vault.

## Second brain and the wiki context pack

Mission Centre also has a separate, older feature: a per-profile **wiki vault** that is summarised into a
context pack at every project launch ([Context Pack for the Agent](MISSION-CENTRE.md#context-pack-for-the-agent)).
The two can be the same folder: the second brain's notes use the same `title`/`summary` frontmatter, so adding
it under `wikiVaults` for a profile puts the related notes in that profile's context pack too.
