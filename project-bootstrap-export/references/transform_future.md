# Future Exporters

## Jira CSV Export (Planned)

Target format: Jira CSV bulk import format.
Each milestone becomes an Epic. Each deliverable becomes a Story under its Epic.
Resources map to Assignee fields.

Key Jira CSV columns:
- `Issue Type` (Epic / Story)
- `Summary`
- `Description`
- `Epic Name` (for Stories: parent milestone name)
- `Epic Link` (for Stories: parent Epic key)
- `Assignee`
- `Due Date`
- `Labels` (milestone amount as label for Epics)

Status: Not yet implemented. Schema and prompt design ready.
Transform script: `scripts/transform_jira.js` (to be created)

---

## Excel Export (Planned)

Target format: Excel workbook (.xlsx) with two sheets:
1. **Project Plan** — Gantt-style table: milestone/deliverable, start, end, owner, status, amount
2. **Resources** — Resource list with allocation % and date range

Useful for PMs who don't use MS Project or Jira, and for sharing with customers.

Status: Not yet implemented. Schema and prompt design ready.
Transform script: `scripts/transform_excel.js` (to be created)

---

## Adding New Exporters

To add a new export target:
1. Create `references/transform_<target>.md` describing the output format and field mapping
2. Create `scripts/transform_<target>.js` (or .py) implementing the transform
3. Add the new format to the `## Supported Export Formats` section in SKILL.md
4. The extract stage is unchanged — the intermediate JSON schema is the stable interface
