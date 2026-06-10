# Claude Skills

A collection of skills for Claude Code.

## Available Skills

| Skill | Description |
|---|---|
| [project-bootstrap-export](./project-bootstrap-export/) | Extracts structured project data from SOW, PO, and cost sheet documents, then exports to MS Project XML (with Jira and Excel planned). |
| [diary](./diary/) | Maintains a per-project development diary capturing the narrative of how code got built — what was tried, what broke, where direction changed, what was learned. |
| [kanban](./kanban/) | Per-project visual kanban board for Claude Code, backed by a self-contained [rewritable](https://github.com/ikangai/rewritable) HTML file. Cards have status, priority, tags, assignee, notes. CLI for Claude, drag-and-drop in the browser for humans. [Changelog](./kanban/CHANGELOG.md). |
| [right-sizing-model-selection](./right-sizing-model-selection/) | Routes every task to the cheapest model that meets the quality bar — Claude tiers, local LM Studio models, and OpenRouter — using empirical probing, public-benchmark priors, and a persistent per-machine knowledge base instead of guesses. |

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

This repo is also a Claude Code **plugin marketplace**. Plugins bundle hooks,
commands, and skills together and install via `/plugin`.

| Plugin | Description |
|---|---|
| [groupchat](./groupchat/) | Shared chat bus for parallel Claude Code instances working one repo — coordinate via hooks, @mentions, a team barrier, and token tracking. [Changelog](./groupchat/CHANGELOG.md). |

```
/plugin marketplace add ikangai/claude-skills
/plugin install groupchat
```

## License

MIT
