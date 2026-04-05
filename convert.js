#!/usr/bin/env node
/**
 * convert.js — Convert a OneNote .one or .onepkg file to HTML using the
 * Joplin WASM converter extracted from the Joplin AppImage.
 *
 * Usage:
 *   node convert.js <input.one|input.onepkg> <output_dir>
 *
 * The pkg/ directory (containing renderer.js, renderer_bg.wasm, snippets/)
 * must exist next to this script. Run extract-wasm.sh first if it doesn't.
 *
 * Exit codes:
 *   0  success (warnings are printed but not fatal)
 *   1  error (bad arguments, missing files, or converter threw)
 */

'use strict';

const path = require('path');
const fs   = require('fs');

// ── Load converter ──────────────────────────────────────────────────────────
const pkgDir = path.join(__dirname, 'pkg');
if (!fs.existsSync(path.join(pkgDir, 'renderer.js'))) {
    console.error('ERROR: pkg/renderer.js not found. Run ./extract-wasm.sh first.');
    process.exit(1);
}

const { oneNoteConverter } = require(path.join(pkgDir, 'renderer.js'));

// ── Args ────────────────────────────────────────────────────────────────────
const [,, inputFile, outputDir] = process.argv;

if (!inputFile || !outputDir) {
    console.error('Usage: node convert.js <input.one|input.onepkg> <output_dir>');
    process.exit(1);
}

const absInput  = path.resolve(inputFile);
const absOutput = path.resolve(outputDir);
// baseDir must end with path separator — it's used to resolve embedded files
// for .one files it is the directory containing the file;
// for .onepkg it is typically the same.
const baseDir = path.dirname(absInput) + path.sep;

if (!fs.existsSync(absInput)) {
    console.error('ERROR: Input file not found:', absInput);
    process.exit(1);
}

fs.mkdirSync(absOutput, { recursive: true });

console.log('Input:    ', absInput);
console.log('Output:   ', absOutput);
console.log('Base dir: ', baseDir);
console.log('Running converter...');
console.log('');

// ── Convert ─────────────────────────────────────────────────────────────────
let converterFailed = false;
const failedPages = [];   // pages we know failed (from exception message)
const missingPages = [];  // pages in index but not on disk

try {
    oneNoteConverter(absInput, absOutput, baseDir);
} catch (err) {
    const msg = err.message || String(err);
    console.error('Converter ERROR:', msg);
    // The WASM runtime appends "near page <name>)" at the end of the location info
    const nearPage = msg.match(/near page (.+)\)\s*$/m);
    if (nearPage) {
        const pageName = nearPage[1].trim();
        console.error('  FAILED PAGE:', pageName);
        failedPages.push(pageName);
    }
    converterFailed = true;
}

// ── Identify missing pages: compare section index links vs files on disk ─────
const sectionName  = path.basename(absInput, path.extname(absInput));
const sectionIndex = path.join(absOutput, sectionName + '.html');

if (fs.existsSync(sectionIndex)) {
    const indexHtml = fs.readFileSync(sectionIndex, 'utf8');
    const sectionDir = path.join(absOutput, sectionName);
    const linkRe = /href="\/[^"]+\/([^"]+\.html)"/g;
    let m;
    while ((m = linkRe.exec(indexHtml)) !== null) {
        const filename = decodeURIComponent(m[1]);
        if (!fs.existsSync(path.join(sectionDir, filename))) {
            missingPages.push(filename.replace(/\.html$/, ''));
        }
    }
    if (missingPages.length > 0) {
        console.error('');
        console.error(`WARNING: ${missingPages.length} page(s) in index but missing on disk:`);
        for (const t of missingPages) console.error('  MISSING PAGE: ' + t);
    }
}

// ── Write per-section failure log (read by generate-summary.js) ──────────────
const allFailed = [...new Set([...failedPages, ...missingPages])];
const logPath = path.join(absOutput, `${sectionName}-failures.json`);
if (allFailed.length > 0) {
    fs.writeFileSync(logPath, JSON.stringify({ section: sectionName, failed: allFailed }, null, 2));
} else if (fs.existsSync(logPath)) {
    fs.unlinkSync(logPath); // clean up old log if section now converts cleanly
}

if (converterFailed) process.exit(1);

// ── Print output tree ────────────────────────────────────────────────────────
console.log('Done. Output files:');

function walk(dir, indent) {
    let entries;
    try { entries = fs.readdirSync(dir, { withFileTypes: true }); }
    catch { return; }
    for (const e of entries) {
        console.log(indent + e.name + (e.isDirectory() ? '/' : ''));
        if (e.isDirectory()) walk(path.join(dir, e.name), indent + '  ');
    }
}
walk(absOutput, '  ');
