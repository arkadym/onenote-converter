# OneNote → HTML Converter

Standalone toolkit to convert Microsoft OneNote `.one` / `.onepkg` files to HTML
using the WASM converter bundled inside the [Joplin](https://joplinapp.org/) desktop app.

No Joplin account needed. No GUI. Runs entirely offline.

**License: [Mozilla Public License 2.0](LICENSE)**

The Rust source code in `src/` is taken from Joplin's
[`packages/onenote-converter`](https://github.com/laurent22/joplin/tree/dev/packages/onenote-converter)
sub-package, which is itself published under MPL-2.0 (distinct from the rest of
Joplin which uses AGPL-3.0). Because we modify those files, MPL-2.0 propagates to
our changes under the file-level copyleft requirement of that licence. The toolkit
scripts (`*.js`, `*.sh`) are original work released under the same MPL-2.0 licence
for consistency.

---

## How It Works

Joplin ships a Rust-compiled WASM module (`onenote-converter`) inside its Electron
`app.asar` bundle. `extract-wasm.sh` pulls it out and fixes the stray leading bytes
that result from asar boundary alignment. Once extracted, `convert.js` calls the
WASM synchronously via Node.js.

---

## Requirements

| Tool | Install |
|------|---------|
| Node.js ≥ 16 | `sudo apt install nodejs` |
| npx (comes with npm) | `sudo apt install npm` |
| cabextract (for `.onepkg`) | `sudo apt install cabextract` |
| Joplin AppImage | Download from https://joplinapp.org/download/ |

---

## Step 1 — Extract the WASM package

Run this **once** per Joplin version. It populates the `pkg/` directory.

```bash
./extract-wasm.sh [/path/to/Joplin-X.Y.Z.appimage]
```

If the AppImage is in `/opt/apps/AppImage/`, the script finds it automatically.

After extraction you will have:

```
pkg/
  renderer.js
  renderer_bg.wasm
  snippets/
    parser-utils-.../
      node_functions.js
```

---

## Step 2 — Convert files

### Single `.one` section

```bash
node convert.js Notes.one ./output/
```

### Single `.onepkg` notebook (CAB archive containing multiple `.one` sections)

First extract the CAB, then convert each `.one`:

```bash
mkdir -p extracted/MyNotebook
cabextract -d extracted/MyNotebook MyNotebook.onepkg
node convert.js extracted/MyNotebook/Section1.one ./output/MyNotebook/
node convert.js extracted/MyNotebook/Section2.one ./output/MyNotebook/
```

Or use the batch script which does this automatically:

```bash
./batch-convert.sh MyNotebook.onepkg ./output/
```

### Whole directory of notebooks

```bash
./batch-convert.sh ~/OneNote/ ./output/
```

Processes every `.onepkg` and `.one` in the directory.

---

## Output Structure

```
output/
  NotebookName/
    SectionName/
      PageTitle.html
      PageTitle2.html
      embedded-image.jpg
      attached-file.pdf
      ...
```

Each HTML page is self-contained and links to sibling files by relative path.

---

## Step 3 — Generate a conversion summary

After converting, run `generate-summary.js` against the output directory to produce
`SUMMARY.md` — a Markdown report with stats and any error details:

```bash
node generate-summary.js ./output/NotebookName/
```

The report contains:

- **Statistics table** — Total / Converted / Missing / Errors per section.
- **Failed / Missing Pages** — Pages in the index that were not produced on disk.
- **Error Details table** — One row per error entry from each section's `*-Errors.html`,
  showing which section, which page, and the exact error message.

---

## Known Issues & Workarounds

### 1. Password-protected sections in `.onepkg`

Some `.onepkg` archives have individual `.one` sections that are encrypted (even if
the notebook has no password set in OneNote — it can be a legacy protection). These
sections fail with:

```
Converter ERROR: Unexpected end of file: Getting u32 (le)
```

**Workaround:** Open the notebook in OneNote, remove section protection, then export
that section as a separate `.one` file. Pass it directly to `convert.js` instead of
the version from the CAB.

### 2. Pages with unknown element types (error `0x60019`)

Some pages with complex embedded objects fail silently — only that page is skipped,
the rest of the section converts fine.

### 3. Corrupt embedded file references (`<invfdo>`)

Pages with broken embedded image references (`<invfdo>`) are now **partially
converted** — the broken item is skipped and the page is saved with all other
content. The page appears in `*-Errors.html` under the section's output directory
so it can be reviewed. Previously the whole page (and sometimes the whole section)
would fail.

### 4. Truncated CAB extraction

`cabextract` can sometimes produce truncated files for large sections. Compare file
sizes with the original (use `7z l` on the `.onepkg`) and re-extract if needed.

---

## Updating for a New Joplin Version

Just re-run `extract-wasm.sh` pointing at the new AppImage:

```bash
./extract-wasm.sh /opt/apps/AppImage/Joplin-3.6.0.appimage
```

The internal asar path to the renderer may change between versions — the script
searches for it automatically.

---

## File Reference

| File | Purpose |
|------|---------|
| `extract-wasm.sh` | Extracts WASM from Joplin AppImage into `pkg/` |
| `convert.js` | Converts a single `.one` or `.onepkg` to HTML |
| `batch-convert.sh` | Batch wrapper for directories of notebooks |
| `generate-summary.js` | Scans output dir and produces `SUMMARY.md` |
| `build.sh` | Builds WASM from source in a sandboxed local Rust env |
| `upstream-sync.sh` | Syncs Rust source from a Joplin release tag into `src/` |
| `deploy-pkg.sh` | Copies a freshly built `pkg/` into the toolkit |
| `src/` | Rust crates from upstream Joplin (managed by `upstream-sync.sh`) |
| `pkg/` | Auto-generated by `extract-wasm.sh` or `build.sh` — do not edit manually |

---

## Our Changes vs Upstream Joplin

This repo tracks upstream Joplin Rust source on `master` (currently **v3.5.13**)
and keeps our patches on the `onenote-converter` branch.

### Branch strategy

```
master             ← upstream Joplin Rust source (synced by upstream-sync.sh)
onenote-converter  ← our patches on top of master
```

---

### Patch 1 — Don't abort the whole section on page render errors

**File:** `src/renderer/src/section.rs`

**Problem:** After writing `Errors.html`, `render()` returned `Err(RenderFailed)`.
This bubbled up as an uncaught WASM exception in `convert.js`, marking the *entire
section* as failed even though every other page had already been saved to disk.

**Change:** Removed the trailing error return. The function now always returns
`Ok(RenderedSection { section_dir })`. Errors are documented in `Errors.html` and
linked from the section ToC; no exception is thrown.

```diff
-        if errors_path.is_some() {
-            Err(ErrorKind::RenderFailed(...).into())
-        } else {
-            Ok(RenderedSection { section_dir })
-        }
+        // Always return Ok — failed pages are documented in Errors.html
+        Ok(RenderedSection { section_dir })
```

---

### Patch 2 — Structured error entries with page name and detail

**Files:** `src/renderer/src/templates/errors.rs`, `src/renderer/src/templates/errors.html`

**Problem:** `Errors.html` rendered a flat `Vec<String>` of raw debug strings with
no indication of which page had failed or why.

**Change:** Introduced `ErrorEntry { page_name: String, detail: String }`. The
template now renders the page title in `<strong>` and the error in `<code>`.

```diff
+pub(crate) struct ErrorEntry {
+    pub(crate) page_name: String,
+    pub(crate) detail: String,
+}
```

```diff
-<li>{{ entry }}</li>
+<li><strong>{{ entry.page_name }}</strong>{% if !entry.detail.is_empty() %} — <code>{{ entry.detail }}</code>{% endif %}</li>
```

Parse-time errors (where no page title is available) use `"Unknown page"` as the
name; render-time errors use the actual page title.

---

### Patch 3 — Skip broken content items; save the page instead of aborting

**Files:** `src/parser/src/onenote/page.rs`, `src/renderer/src/page/mod.rs`

**Problem (parser):** `parse_page()` collected content items with
`collect::<Result<_>>()?`. A single broken embedded image reference (`<invfdo>`)
returned `Err(ResolutionFailed)`, which killed the whole page.

**Change (parser):** Replaced the fallible collect with `filter_map`. Failed items
are logged and recorded in the new `skipped_items: Vec<String>` field on `Page`;
the remaining content is returned normally.

```diff
+    let mut skipped_items: Vec<String> = Vec::new();
     let contents = data.content.into_iter()
-        .map(|id| parse_page_content(id, page_space.clone()))
-        .collect::<Result<_>>()?;
+        .filter_map(|id| match parse_page_content(id, page_space.clone()) {
+            Ok(c)  => Some(c),
+            Err(e) => { skipped_items.push(format!("{}", e)); None }
+        })
+        .collect();
```

**Change (renderer):** `render_page()` content loop no longer propagates per-item
errors. Instead it emits an HTML comment and continues.

```diff
-        .map(|c| self.render_page_content(c))
-        .collect::<Result<String>>()?;
+        .map(|c| match self.render_page_content(c) {
+            Ok(html) => html,
+            Err(e)   => format!("<!-- content item skipped: {} -->", e),
+        })
+        .collect();
```

---

### Patch 4 — Report partially-converted pages in Errors.html

**Files:** `src/parser/src/onenote/page.rs`, `src/renderer/src/section.rs`

**Problem:** After Patch 3, pages with skipped items were saved successfully but
silently — `Errors.html` only listed pages that *failed* entirely, so skipped items
went unnoticed.

**Change:** After a successful page render, `section.rs` checks `page.skipped_items`.
For every skipped item an `ErrorEntry` is pushed, naming the page as
`"PageTitle (partial — item skipped)"` with the error detail.

```diff
+    if !page.skipped_items.is_empty() {
+        let title = page.title_text().unwrap_or_else(|| "Untitled page".into());
+        for detail in &page.skipped_items {
+            errors.push(ErrorEntry {
+                page_name: format!("{} (partial — item skipped)", title),
+                detail: detail.clone(),
+            });
+        }
+    }
```

---

### Toolkit additions / fixes

| Script | Change |
|--------|--------|
| `generate-summary.js` | New — scans output dir, parses `*-Errors.html`, writes `SUMMARY.md` with a stats table and a full error-details table |
| `build.sh` | New — sandbox build: keeps `.rustup/` and `.cargo/` inside the repo, auto-bootstraps Rust + wasm-pack on first run |
| `upstream-sync.sh` | New — sparse-clones a Joplin release tag, copies 4 Rust crates into `src/`, records version in `src/.joplin-version` |
| `extract-wasm.sh` | Fixed for asar v3.2.0: replaced broken `npx asar extract-file` with `npx asar extract` + selective copy |

---

### Updating for a new Joplin release

```bash
git checkout master
./upstream-sync.sh vX.Y.Z
git commit -m "chore: sync upstream Joplin vX.Y.Z"
git push
git checkout onenote-converter
git merge master   # resolve any conflicts with our patches
git push
```
