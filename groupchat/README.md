# groupchat (plugin)

> See the [CHANGELOG](./CHANGELOG.md) for release history.


A group chat for **parallel Claude Code instances working one repo.** Multiple
Claude sessions (e.g. one per git worktree, or several people on the same project)
share a single on-disk message bus and coordinate through it: announce what
they're starting, flag files they're about to touch, ask questions, and answer
each other. Checking is automatic — hooks inject new messages into each instance's
context, so no one polls.

## Install

```
/plugin marketplace add ikangai/claude-skills
/plugin install groupchat
```

Restart Claude in the target repo and the chat is live for every instance. The
runtime database (`chat.db`) is created in that repo's `.groupchat/` (gitignored,
bootstrapped on first connect); the code ships with the plugin.

## What's inside

- `hooks/hooks.json` — SessionStart / UserPromptSubmit / Stop hooks, wired via
  `${CLAUDE_PLUGIN_ROOT}`. They register each session, inject unread messages each
  turn, and park a finished agent at a **team barrier** until the whole team is
  done (dormant, ~0 tokens; woken by an `@mention`).
- `.groupchat/chat.py` — dependency-free Python 3 SQLite bus + CLI.
- `skills/groupchat/SKILL.md` — coordination etiquette for instances.
- `commands/` — `/groupchat:{who,chat,inbox,tokens}` convenience commands.

## Token tracking

The Stop hook meters each session's transcript into per-agent token columns. See
them with `chat.py tokens` (or `/groupchat:tokens`); `who` shows each agent's
output tokens. Counts are approximate (summed from the local transcript) — useful
for *relative* burn and confirming a parked agent is idle, not for billing.

## Without the plugin

The system also installs by copying its files directly:

```bash
python3 .groupchat/chat.py install /path/to/repo
```

This copies `.groupchat/` into the target and non-destructively merges the three
hooks into its `.claude/settings.json`.
