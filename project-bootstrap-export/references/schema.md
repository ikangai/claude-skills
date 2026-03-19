# Project Bootstrap Schema

All extractors output this schema. All exporters consume it.
This is the single contract between the extract and transform stages.

```json
{
  "project": {
    "name": "string",
    "code": "string | null",
    "po_number": "string | null",
    "customer": "string",
    "start_date": "YYYY-MM-DD",
    "end_date": "YYYY-MM-DD",
    "currency": "string (ISO 4217, e.g. EUR, USD)",
    "total_value": "number",
    "business_unit": "string | null",
    "project_manager": "string | null",
    "account_manager": "string | null",
    "payment_terms_days": "number | null"
  },
  "milestones": [
    {
      "id": "string (e.g. M01, M02)",
      "name": "string (the invoice trigger description)",
      "amount": "number",
      "planned_date": "YYYY-MM-DD (derived from plannedMonth if only month given)",
      "currency": "string"
    }
  ],
  "deliverables": [
    {
      "id": "string (e.g. D01, D02)",
      "title": "string",
      "description": "string | null",
      "milestone_id": "string | null (parent milestone)",
      "planned_date": "YYYY-MM-DD | null",
      "acceptance_condition": "string | null"
    }
  ],
  "resources": [
    {
      "id": "string (e.g. R01, R02)",
      "name": "string (person name or role name if no person assigned)",
      "role": "string | null",
      "level": "string | null (Junior/Mid/Senior)",
      "allocation_percent": "number (0-100)",
      "start_date": "YYYY-MM-DD | null",
      "end_date": "YYYY-MM-DD | null",
      "person_days": "number | null (from cost sheet manpower)",
      "daily_rate": "number | null"
    }
  ],
  "suppliers": [
    {
      "id": "string (e.g. S01, S02)",
      "name": "string",
      "description": "string | null",
      "amount": "number",
      "currency": "string",
      "planned_date": "YYYY-MM-DD | null",
      "payment_terms_days": "number | null"
    }
  ],
  "items": [
    {
      "id": "string (e.g. I01, I02)",
      "name": "string",
      "vendor": "string | null",
      "category": "string | null (hardware/software/license/third-party)",
      "quantity": "number | null",
      "unit_cost": "number | null",
      "unit_selling_price": "number | null",
      "currency": "string"
    }
  ],
  "special_conditions": [
    {
      "type": "string (retention/penalty/approval/other)",
      "description": "string",
      "percentage": "number | null",
      "amount": "number | null"
    }
  ],
  "extraction_notes": {
    "missing_fields": ["string — fields that could not be extracted and why"],
    "ambiguities": ["string — ambiguities resolved during extraction and how"],
    "data_quality_issues": ["string — data quality issues in the source document"]
  }
}
```

## Date Handling Rules

- If only a month is given (e.g. "M2026", "April 2026"), derive a date as the last working day of that month.
- If a relative month index is given (e.g. M1, M2 relative to project start), compute the calendar date from `project.start_date`.
- Always output ISO 8601 format: `YYYY-MM-DD`.
- If no date is available, use `null` — never invent a date.

## ID Assignment Rules

- Milestones: M01, M02, M03...
- Deliverables: D01, D02, D03...
- Resources: R01, R02, R03...
- Suppliers: S01, S02, S03...
- Items: I01, I02, I03...
- IDs must be stable within a single extraction run.

## Linkage Rules

- The canonical link between deliverables and milestones is `deliverable.milestone_id`.
- Do not duplicate this link on the milestone side — deliverables reference milestones, not the other way around.

## Confidence & Gaps

When fields cannot be extracted with confidence, set them to `null` rather than guessing.
Use the `extraction_notes` object to record what was missing, ambiguous, or problematic.
Every extraction must include `extraction_notes` — even if all arrays are empty.
