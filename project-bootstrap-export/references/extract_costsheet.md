# Cost Sheet Extraction Prompt

## Purpose
Extract structured project data from a cost sheet Excel file.
Cost sheets vary wildly in format across teams and geographies.
The extractor must handle the full spectrum from clean to chaotic.

## Prompt

```
You are extracting structured project data from a project cost sheet.
Cost sheets vary widely in format — do not assume fixed column positions or headers.
Read the document as a human would: understand context, infer structure, extract meaning.

Extract ALL of the following, wherever they appear:

1. PROJECT HEADER INFORMATION
   - Project name, code, opportunity ID
   - Customer name
   - Start and end dates
   - Currency
   - Business unit
   - Account manager
   - Payment terms (days)

2. PLANNED INVOICES / MILESTONES
   - Each planned invoice row
   - Invoice/milestone ID
   - Description (the milestone name — e.g. "UAT Sign-off", "Upon Contract Signing")
   - Amount (net, before tax)
   - Planned month or date
   - Currency

3. MANPOWER
   - Each role or person listed
   - Role name and seniority level
   - Number of person-days
   - Daily cost rate and daily selling rate
   - Office/location

4. ITEMS, PRODUCTS, LICENSES
   - Each item (hardware, software, licenses, 3rd party products)
   - Item name, vendor, quantity
   - Unit cost and unit selling price
   - Category (hardware/software/license/third-party)
   - Map these to the items array in the schema

5. OUTGOING PAYMENTS / SUPPLIERS
   - Each outgoing payment to a supplier
   - Supplier name, description
   - Amount, currency
   - Planned month
   - Payment terms

Output a single valid JSON object conforming to the Project Bootstrap Schema.
Map manpower entries to resources in the schema.
Map planned invoices to milestones in the schema.
Map outgoing payments to suppliers in the schema.
Map hardware/software/licenses to items in the schema.
Include the extraction_notes object with missing_fields, ambiguities, and data_quality_issues arrays.
Do not include any text outside the JSON.

Cost Sheet Content:
[DOCUMENT CONTENT]
```

## Usage Notes

- "Resource Rate/Month", "Monthly Billing Rate", "Day Rate" — all mean daily/monthly rate; normalize to daily.
- Planned month expressed as "M1", "M2" etc. is relative to project start — resolve to calendar dates.
- Planned month expressed as "M2026" means somewhere in that calendar month — use last working day of month.
- Some cost sheets embed deliverables as footnotes or comments — extract them.
- Grand total rows should not be extracted as line items.
- If currency symbols are inconsistent, flag in extraction_notes.data_quality_issues and default to the header currency.
- Tax amounts on invoices should be noted in extraction_notes but not added to milestone amounts (use net amounts).
