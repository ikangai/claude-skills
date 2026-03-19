# MS Project XML Transform

## Purpose
Transform the Project Bootstrap JSON schema into a Microsoft Project XML file (.xml).
This is a one-time bootstrap export — not a sync. The PM takes the file and manages
the schedule in MS Project from that point forward.

## Output Format
MS Project XML (compatible with MS Project 2010 and later).
File extension: `.xml`
The PM opens it via File > Open in MS Project.

## Transform Script
Use `scripts/transform_msproject.js` to generate the XML.

```
node scripts/transform_msproject.js <input.json> <output.xml>
```

Or pass JSON via stdin:
```
cat project.json | node scripts/transform_msproject.js > project.xml
```

## Structure Produced

```
Project (summary)
├── Milestone: M01 - Upon Contract Signing           [standalone milestone]
├── Requirements Sign-off (summary)                   [has deliverables]
│   ├── M02 - Payment: Requirements Sign-off          [milestone marker]
│   ├── Task: D01 - Business Requirements Doc
│   └── Task: D02 - UX/UI Design Mockups
├── UAT Sign-off (summary)
│   ├── M03 - Payment: UAT Sign-off                   [milestone marker]
│   └── Task: D03 - UAT Test Results Report
├── Go-Live (summary)
│   ├── M04 - Payment: Go-Live                        [milestone marker]
│   └── Task: D04 - Production Deployment
├── Milestone: M05 - Warranty Period End              [standalone milestone]
└── Other Deliverables (summary)
    └── Task: D05 - Technical Documentation
```

- Milestones without deliverables appear as standalone milestone tasks (Duration=0)
- Milestones with deliverables become summary groups containing:
  - A child milestone task (preserving the payment event as a diamond marker)
  - Deliverable tasks as siblings
- Ungrouped deliverables (no milestone_id) collect under "Other Deliverables"
- Resources are added to the resource pool with their allocation %
- Resource assignments are not auto-generated — the PM assigns in MS Project

## Key MS Project XML Fields

| Schema field | MS Project XML element |
|---|---|
| project.name | `<Name>` in `<Project>` |
| project.start_date | `<StartDate>` in `<Project>` |
| project.end_date | `<FinishDate>` in `<Project>` |
| project.currency | `<CurrencySymbol>` (converted from ISO code to symbol) |
| milestone.name | `<Name>` in `<Task>` |
| milestone.planned_date | `<Finish>` in `<Task>`, Duration=PT0H0M0S |
| milestone.amount | `<Notes>` in `<Task>` (formatted amount as note) |
| deliverable.title | `<Name>` in `<Task>` |
| deliverable.planned_date | `<Finish>` in `<Task>` |
| resource.name | `<Name>` in `<Resource>` |
| resource.allocation_percent | `<MaxUnits>` in `<Resource>` (as decimal, e.g. 0.8) |

## Outline Numbering

Tasks use dotted outline numbers (e.g. "1", "1.1", "1.1.1") matching the MS Project WBS hierarchy.

## Notes for the PM
The exported file is a starting point. In MS Project after import:
- Assign resources to specific deliverable tasks
- Set task dependencies (predecessors) — these are not in CompassAI data
- Adjust milestone dates if they were derived from month-only data
- Add sub-tasks beneath deliverables as needed
- Review deliverable durations (default: 1 day) and adjust to actual estimates
