# Customer PO Extraction Prompt

## Purpose
Extract structured project data from a Customer Purchase Order (PO) document.
The Customer PO is issued by the customer to Compass — it is the financial authorization document.
It authorizes specific amounts for specific scopes.

## Prompt

```
You are extracting structured project data from a Customer Purchase Order (PO) document.

A Customer PO is issued by the customer to authorize payment for a project or set of deliverables.
It is NOT generated internally — it comes from the customer.

Extract ALL of the following:

1. PROJECT INFORMATION
   - PO number / reference → map to project.po_number
   - Customer name and address
   - Supplier/vendor name (Compass entity)
   - Total authorized amount and currency
   - PO issue date
   - Payment terms (days)
   - Project name or reference (if stated)

2. LINE ITEMS / MILESTONES
   - Each line item in the PO
   - Description of the line item
   - Amount authorized
   - Planned delivery date (if stated)

3. SPECIAL CONDITIONS
   - Retention clauses (e.g. "10% held until project completion")
   - Penalty clauses for late delivery
   - Approval or sign-off requirements before payment
   - Map these to the special_conditions array with appropriate type

Output a single valid JSON object conforming to the Project Bootstrap Schema.
Map PO line items to milestones in the schema.
Map the PO number to project.po_number.
Include the extraction_notes object with missing_fields, ambiguities, and data_quality_issues arrays.
Do not include any text outside the JSON.

Customer PO Document:
[DOCUMENT CONTENT]
```

## Usage Notes

- PO line items map to milestones — each authorized payment becomes a milestone.
- Retention clauses are critical: map them to `special_conditions` with `type: "retention"`.
- Penalty clauses map to `special_conditions` with `type: "penalty"`.
- The PO authorized total is the validation figure — cross-check against the cost sheet invoice schedule total.
- POs often contain legal boilerplate that is not project data — skip it.
- POs rarely contain deliverables, resources, or items — leave those arrays empty if not found.
