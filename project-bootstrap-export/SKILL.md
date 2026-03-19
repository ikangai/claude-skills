---
name: project-bootstrap-export
description: Extracts structured project data (milestones, deliverables, resources, suppliers, items) from project documents (SOW, Customer PO, cost sheets) and exports the result to scheduling tools (MS Project XML, with Jira and Excel planned). This skill should be used when a user wants to bootstrap a project plan from existing documents, export a CompassAI project to MS Project, or transform any combination of SOW/PO/cost sheet into a structured project file ready to open in a scheduling tool.
---

# Project Bootstrap & Export

## Overview

To eliminate manual transcription of project data at every document boundary.
When a SOW, Customer PO, or cost sheet arrives, this skill reads it, extracts structured
project data into a common JSON schema, and transforms it into the PM's scheduling tool of choice.
The PM reviews and confirms the output — she does not transcribe.

## Supported Document Inputs

- **SOW** (Statement of Work) — delivers deliverables, acceptance conditions, milestone names, dates
- **Customer PO** (Purchase Order) — delivers authorized amounts per milestone, payment terms, special conditions
- **Cost Sheet** (Excel) — delivers manpower, invoice schedule, suppliers, items/products

Any combination of the three can be used. The more documents provided, the more complete the output.
If only one document is available, extract what's there and note gaps.

## Supported Export Formats

- **MS Project XML** — ready to open in MS Project 2010+. Use `scripts/transform_msproject.js`.
- **Jira CSV** — planned. See `references/transform_future.md`.
- **Excel** — planned. See `references/transform_future.md`.

## Intermediate Schema

All extractors output a common JSON schema. All exporters consume it.
Read `references/schema.md` before extracting or transforming — it is the single contract
between the extract and transform stages.

## Workflow

### Step 1 — Identify documents available

Determine which documents the user has provided: SOW, PO, cost sheet, or a combination.
If multiple documents are provided, extract each separately then merge the results.

### Step 2 — Extract

For each document type, read the corresponding prompt from the references folder:
- SOW → `references/extract_sow.md`
- Customer PO → `references/extract_po.md`
- Cost sheet → `references/extract_costsheet.md`

Apply the prompt to the document content. Output valid JSON conforming to `references/schema.md`.
The JSON must include the `extraction_notes` object — this replaces any free-text notes after the JSON.

When multiple documents are provided, merge the extracted JSON objects:
- Prefer cost sheet for financial amounts (milestones, suppliers)
- Prefer SOW for deliverable names, descriptions, acceptance conditions
- Prefer PO for authorized totals, payment terms, and special conditions
- Merge resources from both cost sheet (roles/person-days) and named resources in the SOW
- Merge items from cost sheet (primary source) with any items referenced in SOW
- Deduplicate milestones by matching on name similarity, then by date — do not blindly merge by ID position
- Combine `extraction_notes` from all documents into a single object

### Step 3 — Validate the JSON

Before transforming, verify the extracted JSON is complete and sensible:
- Every milestone has a name and a planned_date (or a derivable date)
- Resources have at minimum a name
- project.start_date and project.end_date are present
- Deliverable milestone_id references point to existing milestone IDs
- Flag anything missing to the user before proceeding

You can use `scripts/validate.js` to check the JSON programmatically:
```
node scripts/validate.js extracted.json
```

### Step 4 — Transform

For MS Project XML export:
1. Read references/transform_msproject.md for field mapping and structure
2. Run scripts/transform_msproject.js with the extracted JSON as input:

   node scripts/transform_msproject.js extracted.json project_plan.xml

3. Provide the .xml file to the user for download

For other formats, see references/transform_future.md.

### Step 5 — Summarize for the user

After exporting, provide a brief summary:
- Number of milestones, deliverables, resources, and items in the export
- Fields that were null/missing and what the PM should fill in manually
- Any extraction notes worth flagging (ambiguities, data quality issues)

## Key Principles

- Extract, don't invent: set fields to null rather than guessing. The PM fills gaps.
- PM as reviewer: the output is a draft for PM review, not a final record.
- One-way, one-time: the export is a bootstrap, not a sync.
- Document variety is expected: reason about structure rather than matching fixed patterns.
