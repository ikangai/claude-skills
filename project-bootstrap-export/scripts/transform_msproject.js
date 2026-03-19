#!/usr/bin/env node
/**
 * transform_msproject.js
 * Transforms Project Bootstrap JSON into Microsoft Project XML.
 *
 * Usage:
 *   node transform_msproject.js <input.json> [output.xml]
 *   cat project.json | node transform_msproject.js > project.xml
 *
 * Compatible with MS Project 2010 and later.
 */

const fs = require('fs');
const path = require('path');

// ─── Currency ────────────────────────────────────────────────────────────────

const CURRENCY_SYMBOLS = {
  EUR: '\u20AC', USD: '$', GBP: '\u00A3', JPY: '\u00A5', CHF: 'CHF',
  CAD: 'CA$', AUD: 'A$', CNY: '\u00A5', INR: '\u20B9', BRL: 'R$',
  SEK: 'kr', NOK: 'kr', DKK: 'kr', PLN: 'z\u0142', CZK: 'K\u010D',
  SAR: 'SAR', AED: 'AED', QAR: 'QAR', KWD: 'KWD',
};

function currencySymbol(isoCode) {
  return CURRENCY_SYMBOLS[isoCode] || isoCode || '$';
}

// ─── Input ───────────────────────────────────────────────────────────────────

function readInput() {
  const inputFile = process.argv[2];
  if (inputFile && fs.existsSync(inputFile)) {
    return JSON.parse(fs.readFileSync(inputFile, 'utf8'));
  }
  // Read from stdin using file descriptor 0 (cross-platform)
  try {
    const stdin = fs.readFileSync(0, 'utf8');
    return JSON.parse(stdin);
  } catch {
    console.error('Usage: node transform_msproject.js <input.json> [output.xml]');
    process.exit(1);
  }
}

function validateInput(data) {
  if (!data || typeof data !== 'object') {
    throw new Error('Input must be a JSON object');
  }
  if (!data.project) {
    throw new Error('Missing required "project" object');
  }
  if (!data.project.start_date) {
    throw new Error('Missing required "project.start_date"');
  }
  if (!data.project.end_date) {
    throw new Error('Missing required "project.end_date"');
  }
}

// ─── Helpers ─────────────────────────────────────────────────────────────────

function escapeXml(str) {
  if (!str) return '';
  return String(str)
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&apos;');
}

function toMspDate(dateStr) {
  if (!dateStr) return null;
  const d = new Date(dateStr);
  if (isNaN(d)) return null;
  return d.toISOString().replace(/\.\d{3}Z$/, 'Z');
}

function deriveMilestoneDate(milestone, project, index, total) {
  if (milestone.planned_date) return milestone.planned_date;
  // Fall back: evenly space milestones across project duration
  const start = new Date(project.start_date);
  const end = new Date(project.end_date);
  const span = end - start;
  const offset = (span / (total + 1)) * (index + 1);
  const d = new Date(start.getTime() + offset);
  return d.toISOString().split('T')[0];
}

function formatAmount(amount, currency) {
  if (!amount) return '';
  return `${currencySymbol(currency)} ${Number(amount).toFixed(2)}`;
}

// ─── Outline Numbering ───────────────────────────────────────────────────────

function computeOutlineNumbers(tasks) {
  const counters = new Array(10).fill(0);
  tasks.forEach(t => {
    const level = t.outlineLevel;
    counters[level - 1]++;
    // Reset all deeper levels
    for (let i = level; i < counters.length; i++) {
      counters[i] = 0;
    }
    t.outlineNumber = counters.slice(0, level).join('.');
  });
}

// ─── XML Builders ────────────────────────────────────────────────────────────

function buildResources(resources) {
  if (!resources || resources.length === 0) return '<Resources/>';
  const items = resources.map((r, i) => `
    <Resource>
      <UID>${i + 1}</UID>
      <ID>${i + 1}</ID>
      <Name>${escapeXml(r.name)}</Name>
      <Type>1</Type>
      ${r.role ? `<Notes>${escapeXml(r.role)}${r.level ? ' (' + r.level + ')' : ''}</Notes>` : ''}
      ${r.allocation_percent != null ? `<MaxUnits>${r.allocation_percent / 100}</MaxUnits>` : '<MaxUnits>1</MaxUnits>'}
    </Resource>`).join('');
  return `<Resources>${items}\n  </Resources>`;
}

function buildTasks(milestones, deliverables, project) {
  const tasks = [];
  let uid = 1;

  // Summary task (project root)
  tasks.push({
    uid: uid++,
    name: project.name || 'Project',
    isSummary: true,
    isMilestone: false,
    start: toMspDate(project.start_date),
    finish: toMspDate(project.end_date),
    outlineLevel: 1,
    notes: project.customer ? `Customer: ${project.customer}` : '',
  });

  const milestoneList = milestones || [];
  const deliverableList = deliverables || [];

  milestoneList.forEach((m, mIdx) => {
    const mDate = deriveMilestoneDate(m, project, mIdx, milestoneList.length);
    const mChildren = deliverableList.filter(d => d.milestone_id === m.id);
    const hasSubs = mChildren.length > 0;
    const amountNote = m.amount ? `Payment: ${formatAmount(m.amount, m.currency)}` : '';

    if (hasSubs) {
      // Summary task grouping the milestone and its deliverables
      tasks.push({
        uid: uid++,
        name: m.name || `Milestone ${m.id}`,
        isSummary: true,
        isMilestone: false,
        start: toMspDate(mDate),
        finish: toMspDate(mDate),
        outlineLevel: 2,
        notes: '',
      });

      // Milestone as a child task (preserves the milestone marker)
      tasks.push({
        uid: uid++,
        name: `${m.id} - Payment: ${m.name || 'Milestone'}`,
        isSummary: false,
        isMilestone: true,
        start: toMspDate(mDate),
        finish: toMspDate(mDate),
        outlineLevel: 3,
        notes: amountNote,
        milestoneRef: m.id,
      });

      // Deliverable sub-tasks
      mChildren.forEach(d => {
        tasks.push({
          uid: uid++,
          name: d.title,
          isSummary: false,
          isMilestone: false,
          finish: toMspDate(d.planned_date || mDate),
          outlineLevel: 3,
          notes: [d.description, d.acceptance_condition].filter(Boolean).join(' | '),
          deliverableRef: d.id,
        });
      });
    } else {
      // Standalone milestone (no deliverables)
      tasks.push({
        uid: uid++,
        name: m.name || `Milestone ${m.id}`,
        isSummary: false,
        isMilestone: true,
        start: toMspDate(mDate),
        finish: toMspDate(mDate),
        outlineLevel: 2,
        notes: amountNote,
        milestoneRef: m.id,
      });
    }
  });

  // Ungrouped deliverables (no milestone_id)
  const ungrouped = deliverableList.filter(d => !d.milestone_id);
  if (ungrouped.length > 0) {
    tasks.push({
      uid: uid++,
      name: 'Other Deliverables',
      isSummary: true,
      isMilestone: false,
      start: toMspDate(project.start_date),
      finish: toMspDate(project.end_date),
      outlineLevel: 2,
      notes: '',
    });
    ungrouped.forEach(d => {
      tasks.push({
        uid: uid++,
        name: d.title,
        isSummary: false,
        isMilestone: false,
        finish: toMspDate(d.planned_date || project.end_date),
        outlineLevel: 3,
        notes: [d.description, d.acceptance_condition].filter(Boolean).join(' | '),
        deliverableRef: d.id,
      });
    });
  }

  // Assign sequential IDs and compute outline numbers
  tasks.forEach((t, i) => { t.id = i + 1; });
  computeOutlineNumbers(tasks);

  const xml = tasks.map(t => {
    const lines = [
      `<UID>${t.uid}</UID>`,
      `<ID>${t.id}</ID>`,
      `<Name>${escapeXml(t.name)}</Name>`,
      `<OutlineLevel>${t.outlineLevel}</OutlineLevel>`,
      `<OutlineNumber>${t.outlineNumber}</OutlineNumber>`,
      `<Summary>${t.isSummary ? 1 : 0}</Summary>`,
      `<Milestone>${t.isMilestone ? 1 : 0}</Milestone>`,
    ];

    if (t.isMilestone) {
      lines.push('<Duration>PT0H0M0S</Duration>');
    } else if (!t.isSummary) {
      // Regular tasks get 1-day default duration; PM refines in MS Project
      lines.push('<Duration>PT8H0M0S</Duration>');
    }
    // Summary tasks: omit Duration — MS Project auto-calculates from children

    if (t.start) lines.push(`<Start>${t.start}</Start>`);
    if (t.finish) lines.push(`<Finish>${t.finish}</Finish>`);
    if (t.notes) lines.push(`<Notes>${escapeXml(t.notes)}</Notes>`);

    return `\n    <Task>\n      ${lines.join('\n      ')}\n    </Task>`;
  }).join('');

  return { xml: `<Tasks>${xml}\n  </Tasks>`, taskList: tasks };
}

function buildAssignments(tasks, resources) {
  // Only create assignments when explicit resource-to-deliverable linkage exists.
  // The current schema has no such linkage, so resources are added to the pool
  // but not assigned to tasks. The PM assigns them in MS Project.
  //
  // When the schema adds resource_ids to deliverables, this function should
  // create targeted assignments based on that data.
  return '<Assignments/>';
}

// ─── Main ────────────────────────────────────────────────────────────────────

function transform(data) {
  const { project, milestones, deliverables, resources } = data;

  const resourcesXml = buildResources(resources);
  const { xml: tasksXml, taskList } = buildTasks(milestones, deliverables, project);
  const assignmentsXml = buildAssignments(taskList, resources);

  const startDate = toMspDate(project.start_date) || new Date().toISOString().replace(/\.\d{3}Z$/, 'Z');
  const endDate = toMspDate(project.end_date) || startDate;

  return `<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Project xmlns="http://schemas.microsoft.com/project">
  <SaveVersion>14</SaveVersion>
  <Name>${escapeXml(project.name || 'Project')}</Name>
  <Title>${escapeXml(project.name || 'Project')}</Title>
  <Subject>${escapeXml(project.customer || '')}</Subject>
  <Author>${escapeXml(project.project_manager || '')}</Author>
  <StartDate>${startDate}</StartDate>
  <FinishDate>${endDate}</FinishDate>
  <DefaultTaskType>0</DefaultTaskType>
  <DefaultFixedCostAccrual>3</DefaultFixedCostAccrual>
  <DefaultStandardRate>0</DefaultStandardRate>
  <DefaultOvertimeRate>0</DefaultOvertimeRate>
  <DurationFormat>7</DurationFormat>
  <WorkFormat>1</WorkFormat>
  <CurrencySymbol>${escapeXml(currencySymbol(project.currency))}</CurrencySymbol>
  ${tasksXml}
  ${resourcesXml}
  ${assignmentsXml}
</Project>`;
}

// ─── Run ─────────────────────────────────────────────────────────────────────

try {
  const data = readInput();
  validateInput(data);
  const xml = transform(data);

  const outputFile = process.argv[3];
  if (outputFile) {
    fs.writeFileSync(outputFile, xml, 'utf8');
    console.error(`Written to ${outputFile}`);
  } else {
    process.stdout.write(xml);
  }
} catch (err) {
  console.error('Error:', err.message);
  process.exit(1);
}
