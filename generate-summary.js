#!/usr/bin/env node
/**
 * generate-summary.js — Scan a converter output directory and produce SUMMARY.md
 *
 * Usage:
 *   node generate-summary.js <output_dir>
 */

'use strict';

const fs   = require('fs');
const path = require('path');

const outputDir = process.argv[2];
if (!outputDir || !fs.existsSync(outputDir)) {
    console.error('Usage: node generate-summary.js <output_dir>');
    process.exit(1);
}

// ── Find all section index HTML files ────────────────────────────────────────
// These are top-level .html files that are NOT *-Errors.html
const indexFiles = fs.readdirSync(outputDir)
    .filter(f => f.endsWith('.html') && !f.endsWith('-Errors.html') && f !== 'Errors.html' && f !== 'SUMMARY.html')
    .sort();

const sections = [];
let grandTotal = 0;
let grandConverted = 0;

for (const indexFile of indexFiles) {
    const sectionName = indexFile.replace(/\.html$/, '');
    const indexPath   = path.join(outputDir, indexFile);
    const sectionDir  = path.join(outputDir, sectionName);

    const indexHtml = fs.readFileSync(indexPath, 'utf8');

    // Count total pages linked in index
    const linkRe = /href="\/[^"]+\/([^"]+\.html)"/g;
    const allPages = [];
    let m;
    while ((m = linkRe.exec(indexHtml)) !== null) {
        allPages.push(decodeURIComponent(m[1]));
    }
    const total = allPages.length;

    // Count pages actually on disk
    let onDisk = [];
    if (fs.existsSync(sectionDir)) {
        onDisk = fs.readdirSync(sectionDir).filter(f => f.endsWith('.html'));
    }
    const converted = onDisk.length;

    // Missing from index-vs-disk diff
    const missingFromDiff = allPages
        .filter(filename => !fs.existsSync(path.join(sectionDir, filename)))
        .map(filename => filename.replace(/\.html$/, ''));

    // Failed pages logged by convert.js (includes pages not in index at all)
    const logPath = path.join(outputDir, `${sectionName}-failures.json`);
    let failedFromLog = [];
    if (fs.existsSync(logPath)) {
        try { failedFromLog = JSON.parse(fs.readFileSync(logPath, 'utf8')).failed || []; } catch {}
    }

    // Merge and deduplicate
    const missing = [...new Set([...missingFromDiff, ...failedFromLog])];

    const hasErrors = fs.existsSync(path.join(outputDir, `${sectionName}-Errors.html`));

    sections.push({ sectionName, total, converted, missing, hasErrors });
    grandTotal     += total + failedFromLog.filter(p => !allPages.map(f => f.replace(/\.html$/, '')).includes(p)).length;
    grandConverted += converted;
}

const grandMissing = grandTotal - grandConverted;
const now = new Date().toISOString().replace('T', ' ').slice(0, 19);

// ── Build markdown ────────────────────────────────────────────────────────────
const lines = [];

lines.push(`# Conversion Summary`);
lines.push(`Generated: ${now}`);
lines.push('');

// Stats table
lines.push('## Statistics');
lines.push('');
lines.push('| Section | Total | Converted | Missing |');
lines.push('|---|---:|---:|---:|');

for (const s of sections) {
    const icon    = s.missing.length > 0 ? '⚠' : '✓';
    const missing = s.missing.length > 0 ? `**${s.missing.length}**` : '0';
    lines.push(`| ${icon} ${s.sectionName} | ${s.total} | ${s.converted} | ${missing} |`);
}

lines.push(`| **Total** | **${grandTotal}** | **${grandConverted}** | **${grandMissing}** |`);
lines.push('');

// Failed/missing detail
const sectionsWithIssues = sections.filter(s => s.missing.length > 0);
if (sectionsWithIssues.length === 0) {
    lines.push('All pages converted successfully. 🎉');
} else {
    lines.push('## Failed / Missing Pages');
    lines.push('');
    lines.push('These pages appear in the section index but were not produced on disk.');
    lines.push('Root cause: broken embedded image reference (`<invfdo>`) in the OneNote file.');
    lines.push('');

    for (const s of sectionsWithIssues) {
        lines.push(`### ${s.sectionName} (${s.missing.length} missing)`);
        lines.push('');
        for (const t of s.missing) {
            lines.push(`- ${t}`);
        }
        lines.push('');
    }
}

const summaryPath = path.join(outputDir, 'SUMMARY.md');
fs.writeFileSync(summaryPath, lines.join('\n') + '\n');
console.log(`Summary written to: ${summaryPath}`);
console.log(`  ${grandConverted}/${grandTotal} pages converted, ${grandMissing} missing`);
