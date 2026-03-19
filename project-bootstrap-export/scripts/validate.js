#!/usr/bin/env node
/**
 * validate.js
 * Validates Project Bootstrap JSON against the schema contract.
 *
 * Usage:
 *   node validate.js <input.json>
 *   cat project.json | node validate.js
 *
 * Exits 0 if valid, 1 if errors found.
 */

const fs = require('fs');

// ─── Input ───────────────────────────────────────────────────────────────────

function readInput() {
  const inputFile = process.argv[2];
  if (inputFile && fs.existsSync(inputFile)) {
    return JSON.parse(fs.readFileSync(inputFile, 'utf8'));
  }
  try {
    return JSON.parse(fs.readFileSync(0, 'utf8'));
  } catch {
    console.error('Usage: node validate.js <input.json>');
    process.exit(1);
  }
}

// ─── Validators ──────────────────────────────────────────────────────────────

const ISO_DATE = /^\d{4}-\d{2}-\d{2}$/;
const ID_PATTERNS = {
  milestones: /^M\d{2,}$/,
  deliverables: /^D\d{2,}$/,
  resources: /^R\d{2,}$/,
  suppliers: /^S\d{2,}$/,
  items: /^I\d{2,}$/,
};

function validateDate(value, path) {
  if (value === null || value === undefined) return [];
  if (!ISO_DATE.test(value)) return [`${path}: expected YYYY-MM-DD, got "${value}"`];
  if (isNaN(new Date(value))) return [`${path}: invalid date "${value}"`];
  return [];
}

function validateProject(project) {
  const errors = [];
  if (!project) {
    return ['Missing required "project" object'];
  }
  if (!project.name) errors.push('project.name is required');
  if (!project.customer) errors.push('project.customer is required');
  if (!project.start_date) errors.push('project.start_date is required');
  if (!project.end_date) errors.push('project.end_date is required');

  errors.push(...validateDate(project.start_date, 'project.start_date'));
  errors.push(...validateDate(project.end_date, 'project.end_date'));

  if (project.start_date && project.end_date && project.start_date > project.end_date) {
    errors.push('project.start_date is after project.end_date');
  }
  return errors;
}

function validateArray(arr, name, idPattern) {
  const errors = [];
  if (!arr) return [];
  if (!Array.isArray(arr)) return [`"${name}" must be an array`];

  const ids = new Set();
  arr.forEach((item, i) => {
    const prefix = `${name}[${i}]`;
    if (!item.id) {
      errors.push(`${prefix}.id is required`);
    } else {
      if (ids.has(item.id)) errors.push(`${prefix}.id "${item.id}" is duplicated`);
      ids.add(item.id);
      if (idPattern && !idPattern.test(item.id)) {
        errors.push(`${prefix}.id "${item.id}" does not match expected pattern`);
      }
    }
  });
  return errors;
}

function validateMilestones(milestones) {
  const errors = validateArray(milestones, 'milestones', ID_PATTERNS.milestones);
  if (!milestones) return errors;
  milestones.forEach((m, i) => {
    const prefix = `milestones[${i}]`;
    if (!m.name) errors.push(`${prefix}.name is required`);
    errors.push(...validateDate(m.planned_date, `${prefix}.planned_date`));
  });
  return errors;
}

function validateDeliverables(deliverables, milestoneIds) {
  const errors = validateArray(deliverables, 'deliverables', ID_PATTERNS.deliverables);
  if (!deliverables) return errors;
  deliverables.forEach((d, i) => {
    const prefix = `deliverables[${i}]`;
    if (!d.title) errors.push(`${prefix}.title is required`);
    errors.push(...validateDate(d.planned_date, `${prefix}.planned_date`));
    if (d.milestone_id && !milestoneIds.has(d.milestone_id)) {
      errors.push(`${prefix}.milestone_id "${d.milestone_id}" references non-existent milestone`);
    }
  });
  return errors;
}

function validateResources(resources) {
  const errors = validateArray(resources, 'resources', ID_PATTERNS.resources);
  if (!resources) return errors;
  resources.forEach((r, i) => {
    const prefix = `resources[${i}]`;
    if (!r.name) errors.push(`${prefix}.name is required`);
    if (r.allocation_percent != null && (r.allocation_percent < 0 || r.allocation_percent > 100)) {
      errors.push(`${prefix}.allocation_percent must be 0-100, got ${r.allocation_percent}`);
    }
    errors.push(...validateDate(r.start_date, `${prefix}.start_date`));
    errors.push(...validateDate(r.end_date, `${prefix}.end_date`));
  });
  return errors;
}

function validateSuppliers(suppliers) {
  const errors = validateArray(suppliers, 'suppliers', ID_PATTERNS.suppliers);
  if (!suppliers) return errors;
  suppliers.forEach((s, i) => {
    const prefix = `suppliers[${i}]`;
    if (!s.name) errors.push(`${prefix}.name is required`);
    errors.push(...validateDate(s.planned_date, `${prefix}.planned_date`));
  });
  return errors;
}

function validateItems(items) {
  const errors = validateArray(items, 'items', ID_PATTERNS.items);
  if (!items) return errors;
  items.forEach((item, i) => {
    const prefix = `items[${i}]`;
    if (!item.name) errors.push(`${prefix}.name is required`);
  });
  return errors;
}

function validateExtractionNotes(notes) {
  if (!notes) return ['Missing "extraction_notes" object'];
  const errors = [];
  ['missing_fields', 'ambiguities', 'data_quality_issues'].forEach(key => {
    if (notes[key] && !Array.isArray(notes[key])) {
      errors.push(`extraction_notes.${key} must be an array`);
    }
  });
  return errors;
}

// ─── Main ────────────────────────────────────────────────────────────────────

function validate(data) {
  const errors = [];
  const warnings = [];

  errors.push(...validateProject(data.project));
  errors.push(...validateMilestones(data.milestones));

  const milestoneIds = new Set((data.milestones || []).map(m => m.id));
  errors.push(...validateDeliverables(data.deliverables, milestoneIds));
  errors.push(...validateResources(data.resources));
  errors.push(...validateSuppliers(data.suppliers));
  errors.push(...validateItems(data.items));
  errors.push(...validateExtractionNotes(data.extraction_notes));

  // Warnings (non-blocking)
  if (!data.milestones || data.milestones.length === 0) {
    warnings.push('No milestones found — the export will have no milestone tasks');
  }
  if (!data.resources || data.resources.length === 0) {
    warnings.push('No resources found — the export will have an empty resource pool');
  }
  const nullDateMilestones = (data.milestones || []).filter(m => !m.planned_date);
  if (nullDateMilestones.length > 0) {
    warnings.push(`${nullDateMilestones.length} milestone(s) have no planned_date — dates will be derived`);
  }

  return { errors, warnings };
}

try {
  const data = readInput();
  const { errors, warnings } = validate(data);

  if (warnings.length > 0) {
    console.error(`Warnings (${warnings.length}):`);
    warnings.forEach(w => console.error(`  - ${w}`));
  }

  if (errors.length > 0) {
    console.error(`Errors (${errors.length}):`);
    errors.forEach(e => console.error(`  - ${e}`));
    process.exit(1);
  }

  console.error(`Validation passed. ${warnings.length} warning(s).`);
  process.exit(0);
} catch (err) {
  console.error('Error:', err.message);
  process.exit(1);
}
