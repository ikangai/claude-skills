# Changelog

All notable changes to the groupchat plugin are documented here.

## 0.1.0 — 2026-06-02

Initial release. Packages the group-chat system as a Claude Code plugin and adds
token tracking.

### Added

- **Shared message bus** (`.groupchat/chat.py`) — a dependency-free Python 3
  SQLite database (WAL mode) that all instances on one repo share, plus a CLI
  (`send`, `read`, `inbox`, `who`, `log`, `done`, `expect`, `install`, …).
- **Three hooks** wired via `${CLAUDE_PLUGIN_ROOT}` (`hooks/hooks.json`):
  - `session_start.py` assigns a handle from a fixed pool and injects a briefing
    (active teammates + recent chat).
  - `user_prompt_submit.py` injects messages newer than the agent's cursor before
    each turn, then advances the cursor.
  - `stop.py` blocks on unanswered `@mention`s, then consults a **team barrier** —
    a finished agent **parks** (a blocking sleep-poll in the hook, dormant and
    ~0 tokens) until the whole team is done, waking to answer a teammate's later
    `@mention`. Safety rails: startup guard, dead-agent aging, and a park ceiling.
- **Store resolution anchored to the git common dir**, so every worktree of a
  repo shares one `chat.db`.
- **Runtime `.gitignore` bootstrap** — a freshly created target-repo `.groupchat/`
  gets a `*` ignore on first connect, so the runtime db is never committed.
- **Token tracking.** `stop.py` meters each session's transcript
  (`transcript_path`) into four `agents` columns (`in/out/cache_read/
  cache_create`), added via a guarded `ALTER TABLE` so existing dbs upgrade in
  place. Surfaced by `chat.py tokens` (per-agent + team total) and an output-token
  suffix in `who`. Counts are approximate (summed from the local transcript) —
  useful for *relative* burn and confirming a parked agent is idle, not billing.
- **Usage skill** (`skills/groupchat/SKILL.md`) — coordination etiquette for
  parallel instances.
- **Slash commands** `/groupchat:{who,chat,inbox,tokens}`. They reuse the absolute
  `chat.py` path from the SessionStart briefing rather than `${CLAUDE_PLUGIN_ROOT}`,
  which does not expand in command markdown (Claude Code bug #9354).

### Notes

The runtime `chat.db` is created in the *target* repo's `.groupchat/` (gitignored),
while the code ships with the plugin under `${CLAUDE_PLUGIN_ROOT}`. The legacy
`python3 .groupchat/chat.py install /path/to/repo` copy-in method still works as an
alternative to `/plugin install`.

Do **not** install the plugin in a repo that already wires the hooks via its own
`.claude/settings.json` — both at once would double-fire the hooks.
