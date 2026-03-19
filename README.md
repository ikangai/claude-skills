# Claude Skills

A collection of skills for Claude Code.

## Available Skills

| Skill | Description |
|---|---|
| [project-bootstrap-export](./project-bootstrap-export/) | Extracts structured project data from SOW, PO, and cost sheet documents, then exports to MS Project XML (with Jira and Excel planned). |

## Installation

To install a skill in Claude Code, add it to your `.claude/settings.json`:

```json
{
  "skills": [
    "https://github.com/ikangai/claude-skills/tree/main/project-bootstrap-export"
  ]
}
```

## License

MIT
