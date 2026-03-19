# SOW Extraction Prompt

## Purpose
Extract structured project data from a Statement of Work (SOW) document.
SOWs may be PDFs, Word documents, or plain text. Layouts vary widely.

## Prompt

```
You are extracting structured project data from a Statement of Work (SOW) document.

Your task is to extract ALL of the following, wherever they appear in the document:

1. PROJECT INFORMATION
   - Project name and code (if present)
   - Customer name
   - Start date and end date
   - Total contract value and currency
   - Project manager and account manager names (if mentioned)
   - Payment terms (days)

2. MILESTONES
   - Each payment trigger or invoice milestone
   - The name/description of the milestone (e.g. "UAT Sign-off", "Go-Live")
   - The associated payment amount (if stated)
   - The planned date or month

3. DELIVERABLES
   - Every named deliverable, work product, or acceptance item
   - Its description or acceptance condition
   - Its planned completion date
   - Which milestone it belongs to (if stated or inferable)

4. RESOURCES
   - Named team members or role descriptions
   - Their role, seniority level, allocation percentage
   - Start and end dates of their involvement
   - Person-days if stated

5. SUPPLIERS / SUBCONTRACTORS
   - Any third-party suppliers or subcontractors mentioned
   - Their scope and associated costs

6. SPECIAL CONDITIONS
   - Retention clauses, penalty clauses, approval requirements
   - Any conditions that affect payment or acceptance

Output a single valid JSON object conforming to the Project Bootstrap Schema.
Include the extraction_notes object with missing_fields, ambiguities, and data_quality_issues arrays.
Do not include any text outside the JSON.

SOW Document:
[DOCUMENT CONTENT]
```

## Usage Notes

- SOWs often contain deliverables in multiple places: a summary table, a detailed scope section, and an appendix. Scan the full document.
- Milestone names in SOWs are often acceptance conditions rather than payment labels — treat them as milestone names.
- If payment amounts are not in the SOW, leave `amount: null` on milestones — the cost sheet will provide those.
- Some SOWs list deliverables without milestone groupings — leave `milestone_id: null` and let the PM assign during review.
- SOWs rarely contain items/products — leave the `items` array empty if none are found.
