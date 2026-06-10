# Claude Skills

A collection of skills for Claude Code.

## Available Skills

| Skill | Description |
|---|---|
| [project-bootstrap-export](./project-bootstrap-export/) | Extracts structured project data from SOW, PO, and cost sheet documents, then exports to MS Project XML (with Jira and Excel planned). |
| [diary](./diary/) | Maintains a per-project development diary capturing the narrative of how code got built — what was tried, what broke, where direction changed, what was learned. |
| [kanban](./kanban/) | Per-project visual kanban board for Claude Code, backed by a self-contained [rewritable](https://github.com/ikangai/rewritable) HTML file. Cards have status, priority, tags, assignee, notes. CLI for Claude, drag-and-drop in the browser for humans. [Changelog](./kanban/CHANGELOG.md). |

## Installation

To install a skill in Claude Code, add it to your `.claude/settings.json`:

```json
{
  "skills": [
    "https://github.com/ikangai/claude-skills/tree/main/project-bootstrap-export"
  ]
}
```

## Plugins

Plugins have moved to the dedicated
[ikangai/claude-plugins](https://github.com/ikangai/claude-plugins) marketplace.
In particular, **groupchat** now lives there — if you installed it from this repo,
reinstall from the new marketplace to keep getting updates:

```
/plugin marketplace add ikangai/claude-plugins
/plugin install groupchat
```

## License

MIT
