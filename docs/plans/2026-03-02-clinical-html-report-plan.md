# Clinical HTML Report — Tabbed View Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add a Clinical Summary tab (default) alongside the existing Full Annotation tab in each `{sample}.html` report, surfacing ClinVar sig + stars, CancerVar, active ACMG criteria, gnomAD AF, COSMIC ID, and IGV screenshot without adding new data sources.

**Architecture:** All changes in `excel_to_html_report.py`. Three new module-level helpers, three new methods on `iSeqReportGenerator`, one extended CSS block, one extended JS block, and one modified page generator. The sample-level page (`samples/{sample}.html`) gets the two tabs; individual variant detail pages are unchanged.

**Tech Stack:** Python 3, openpyxl, inline HTML/CSS/JS — no new dependencies.

---

### Task 1: Add three module-level helper functions + unit tests

**Files:**
- Modify: `excel_to_html_report.py` — insert after `_cancervar_tier_badge()` (line ~523)
- Create: `tests/test_html_helpers.py`

**Step 1: Create tests file**

```python
# tests/test_html_helpers.py
import sys, os
sys.path.insert(0, os.path.dirname(os.path.dirname(__file__)))
from excel_to_html_report import clnrevstat_to_stars, _clinvar_sig_badge, _intervar_badge

def test_clnrevstat_practice_guideline():
    html = clnrevstat_to_stars("practice_guideline")
    assert "★★★★" in html
    assert "clnstar-4" in html

def test_clnrevstat_expert_panel():
    assert "★★★" in clnrevstat_to_stars("reviewed_by_expert_panel")

def test_clnrevstat_multiple_submitters():
    assert "★★" in clnrevstat_to_stars(
        "criteria_provided,_multiple_submitters,_no_conflicts")

def test_clnrevstat_single_submitter():
    assert "★" in clnrevstat_to_stars("criteria_provided,_single_submitter")

def test_clnrevstat_no_assertion():
    assert "☆" in clnrevstat_to_stars("no_assertion_criteria_provided")

def test_clnrevstat_conflicting():
    assert "⚠" in clnrevstat_to_stars(
        "conflicting_interpretations_of_pathogenicity")

def test_clnrevstat_empty():
    assert clnrevstat_to_stars("") == ""

def test_clinvar_sig_badge_pathogenic():
    html = _clinvar_sig_badge("Pathogenic")
    assert "clnsig-pathogenic" in html
    assert "Pathogenic" in html

def test_clinvar_sig_badge_likely_pathogenic():
    assert "clnsig-likely-pathogenic" in _clinvar_sig_badge("Likely_pathogenic")

def test_clinvar_sig_badge_vus():
    assert "clnsig-vus" in _clinvar_sig_badge("Uncertain_significance")

def test_clinvar_sig_badge_benign():
    assert "clnsig-benign" in _clinvar_sig_badge("Benign")

def test_clinvar_sig_badge_empty():
    assert _clinvar_sig_badge("") == ""

def test_intervar_badge_pathogenic():
    assert "clnsig-pathogenic" in _intervar_badge("Pathogenic PVS1+PS3")

def test_intervar_badge_empty():
    assert _intervar_badge("") == ""
```

**Step 2: Run tests — expect ImportError (functions not yet defined)**

```bash
python3 -m pytest tests/test_html_helpers.py -v
```
Expected: `ImportError: cannot import name 'clnrevstat_to_stars'`

**Step 3: Add helpers to `excel_to_html_report.py` after `_cancervar_tier_badge()` (line ~523)**

```python
# CLNREVSTAT → star display mapping
_CLNREVSTAT_STARS = {
    "practice_guideline":
        ("★★★★", "clnstar-4"),
    "reviewed_by_expert_panel":
        ("★★★",  "clnstar-3"),
    "criteria_provided,_multiple_submitters,_no_conflicts":
        ("★★",   "clnstar-2"),
    "criteria_provided,_single_submitter":
        ("★",    "clnstar-1"),
    "no_assertion_criteria_provided":
        ("☆",    "clnstar-0"),
    "no_assertion_provided":
        ("☆",    "clnstar-0"),
    "conflicting_interpretations_of_pathogenicity":
        ("⚠",   "clnstar-conflict"),
}


def clnrevstat_to_stars(val: str) -> str:
    """Convert CLNREVSTAT string to a star rating HTML span."""
    if not val:
        return ""
    key = val.strip().lower().replace(" ", "_")
    entry = _CLNREVSTAT_STARS.get(key)
    if entry:
        stars, css_class = entry
    else:
        stars, css_class = "☆", "clnstar-0"
    return f'<span class="clnstar {css_class}" title="{escape(val)}">{stars}</span>'


def _clinvar_sig_badge(sig: str) -> str:
    """Generate ClinVar clinical significance badge HTML."""
    if not sig:
        return ""
    s = sig.lower()
    if ("likely_pathogenic" in s or "likely pathogenic" in s):
        css = "clnsig-likely-pathogenic"
    elif ("likely_benign" in s or "likely benign" in s):
        css = "clnsig-likely-benign"
    elif "pathogenic" in s and "benign" not in s:
        css = "clnsig-pathogenic"
    elif "benign" in s:
        css = "clnsig-benign"
    elif "uncertain" in s or "vus" in s:
        css = "clnsig-vus"
    elif "conflicting" in s:
        css = "clnsig-conflicting"
    else:
        css = "clnsig-other"
    return f'<span class="clnsig-badge {css}">{escape(sig)}</span>'


def _intervar_badge(intervar: str) -> str:
    """Generate InterVar automated classification badge HTML."""
    if not intervar:
        return ""
    s = intervar.lower()
    if "likely pathogenic" in s:
        css = "clnsig-likely-pathogenic"
    elif "likely benign" in s:
        css = "clnsig-likely-benign"
    elif "pathogenic" in s and "benign" not in s:
        css = "clnsig-pathogenic"
    elif "benign" in s:
        css = "clnsig-benign"
    elif "uncertain" in s or "vus" in s:
        css = "clnsig-vus"
    else:
        css = "clnsig-other"
    return f'<span class="intervar-badge {css}">{escape(intervar)}</span>'
```

**Step 4: Run tests — expect all pass**

```bash
python3 -m pytest tests/test_html_helpers.py -v
```
Expected: 15 passed

**Step 5: Commit**

```bash
git add excel_to_html_report.py tests/test_html_helpers.py
git commit -m "feat: add clnrevstat_to_stars, _clinvar_sig_badge, _intervar_badge helpers"
```

---

### Task 2: Extend CSS — tab bar, clinical table, badges, stars, detail cards

**Files:**
- Modify: `excel_to_html_report.py` — `get_css_styles()` return string, append before closing `"""`

**Step 1: Append to the CSS string (before the closing `"""` at line ~481)**

```css
/* ── Tab bar ────────────────────────────────────────────── */
.tab-bar {
    display: flex; gap: 4px;
    margin-bottom: 20px;
    border-bottom: 2px solid var(--border-color);
}
.tab-btn {
    padding: 10px 22px; border: none; background: none;
    font-size: 0.95rem; font-weight: 500; cursor: pointer;
    color: var(--text-muted); border-bottom: 3px solid transparent;
    margin-bottom: -2px; transition: color 0.15s, border-color 0.15s;
}
.tab-btn.active {
    color: var(--secondary-color);
    border-bottom-color: var(--secondary-color);
}
.tab-pane { display: none; }
.tab-pane.active { display: block; }

/* ── Clinical summary table ─────────────────────────────── */
.clinical-summary-table {
    width: 100%; border-collapse: collapse;
    background: white; border-radius: 8px;
    box-shadow: 0 2px 8px rgba(0,0,0,0.08);
    margin-bottom: 24px; overflow: hidden;
}
.clinical-summary-table th {
    background: var(--primary-color); color: white;
    padding: 10px 14px; text-align: left;
    font-size: 0.85rem; font-weight: 600;
}
.clinical-summary-table td {
    padding: 10px 14px; border-bottom: 1px solid var(--border-color);
    font-size: 0.9rem;
}
.clinical-summary-table tbody tr { cursor: pointer; }
.clinical-summary-table tbody tr:hover { background: #f0f4ff; }
.clinical-summary-table tbody tr:last-child td { border-bottom: none; }

/* ── ClinVar significance badges ────────────────────────── */
.clnsig-badge, .intervar-badge {
    display: inline-block; padding: 3px 9px;
    border-radius: 12px; font-size: 0.78rem; font-weight: 600;
    white-space: nowrap;
}
.clnsig-pathogenic        { background: #fde8e8; color: #c0392b; }
.clnsig-likely-pathogenic { background: #fef3e2; color: #d35400; }
.clnsig-vus               { background: #f1f3f5; color: #495057; }
.clnsig-likely-benign     { background: #e2f4f7; color: #148a9e; }
.clnsig-benign            { background: #e6f9ee; color: #1a7a3e; }
.clnsig-conflicting       { background: #fff8e1; color: #856404; }
.clnsig-other             { background: #f1f3f5; color: #495057; }

/* ── ClinVar star ratings ───────────────────────────────── */
.clnstar { font-size: 1rem; letter-spacing: 1px; }
.clnstar-4 { color: #27ae60; }
.clnstar-3 { color: #2980b9; }
.clnstar-2 { color: #8e44ad; }
.clnstar-1 { color: #d35400; }
.clnstar-0 { color: #95a5a6; }
.clnstar-conflict { color: #e67e22; }

/* ── Variant detail cards ───────────────────────────────── */
.variant-detail-card {
    background: white; border-radius: 8px;
    box-shadow: 0 2px 8px rgba(0,0,0,0.08);
    margin-bottom: 16px; overflow: hidden;
}
.variant-detail-card-header {
    display: flex; justify-content: space-between; align-items: center;
    padding: 14px 20px; cursor: pointer;
    background: #f8f9fa; border-bottom: 1px solid var(--border-color);
    gap: 12px;
}
.variant-detail-card-header:hover { background: #f0f4ff; }
.variant-detail-card.collapsed .variant-detail-card-body { display: none; }
.variant-detail-card.collapsed .card-toggle { transform: rotate(-90deg); }
.card-toggle { transition: transform 0.2s; font-size: 1rem; color: var(--text-muted); }
.card-header-left { display: flex; align-items: center; gap: 10px; flex-wrap: wrap; }
.card-header-right { display: flex; align-items: center; gap: 8px; flex-wrap: wrap; }
.card-gene { font-size: 1.1rem; font-weight: 700; color: var(--primary-color); }
.card-hgvs { font-size: 0.88rem; color: #495057; }
.card-hgvsp { font-size: 0.88rem; color: #495057; }
.card-vaf { font-size: 0.85rem; color: var(--text-muted); }
.variant-detail-card-body { padding: 18px 20px; }
.card-detail-row {
    display: flex; align-items: baseline; gap: 8px;
    margin-bottom: 10px; font-size: 0.9rem;
}
.card-detail-label { font-weight: 600; color: var(--primary-color); min-width: 160px; }
.acmg-chips-inline { display: flex; flex-wrap: wrap; gap: 4px; }
.detail-link {
    display: inline-block; padding: 6px 14px;
    background: var(--secondary-color); color: white;
    border-radius: 4px; text-decoration: none; font-size: 0.85rem;
}
.detail-link:hover { background: var(--primary-color); }
```

**Step 2: Verify CSS loads without syntax errors**

```bash
python3 -c "from excel_to_html_report import get_css_styles; print('CSS OK, len=', len(get_css_styles()))"
```
Expected: `CSS OK, len=` (some large number, no exception)

**Step 3: Commit**

```bash
git add excel_to_html_report.py
git commit -m "feat: add tab bar, clinical badge, star, and card CSS"
```

---

### Task 3: Extend JavaScript

**Files:**
- Modify: `excel_to_html_report.py` — `get_javascript()` return string

**Step 1: Replace `get_javascript()` body (line ~485)**

```python
def get_javascript() -> str:
    return """
function togglePanel(header) {
    header.parentElement.classList.toggle('collapsed');
}

function switchTab(tabId) {
    document.querySelectorAll('.tab-btn').forEach(function(b) {
        b.classList.toggle('active', b.dataset.tab === tabId);
    });
    document.querySelectorAll('.tab-pane').forEach(function(p) {
        p.classList.toggle('active', p.id === tabId);
    });
}

function toggleCard(header) {
    header.parentElement.classList.toggle('collapsed');
}

function scrollToCard(cardId) {
    var el = document.getElementById(cardId);
    if (el) {
        el.scrollIntoView({behavior: 'smooth', block: 'start'});
        if (el.classList.contains('collapsed')) {
            el.classList.remove('collapsed');
        }
    }
}
"""
```

**Step 2: Verify**

```bash
python3 -c "from excel_to_html_report import get_javascript; print('JS OK'); print(get_javascript())"
```
Expected: prints all 4 functions without error.

**Step 3: Commit**

```bash
git add excel_to_html_report.py
git commit -m "feat: add switchTab, toggleCard, scrollToCard JS functions"
```

---

### Task 4: Add `_get_active_acmg_criteria` method

**Files:**
- Modify: `excel_to_html_report.py` — add method to `iSeqReportGenerator` after `_computational_section_html` (~line 800)

**Step 1: Add method**

```python
def _get_active_acmg_criteria(self, row_idx: int) -> list:
    """Return list of (label, css_class) for ACMG criteria with evidence.

    Mirrors the active logic in _acmg_section_html:
    a criterion is active when its value is non-empty and not "0".
    """
    active = []
    for group_criteria in ACMG_CRITERIA.values():
        for col_name, label, css_class in group_criteria:
            val = self._val_n(row_idx, col_name)
            if val and val != "0":
                active.append((label, css_class))
    return active
```

**Step 2: Quick smoke test**

```bash
python3 -c "
from excel_to_html_report import iSeqReportGenerator, ACMG_CRITERIA
g = iSeqReportGenerator.__new__(iSeqReportGenerator)
g.headers = ['SAMPLE'] + [c for grp in ACMG_CRITERIA.values() for c,_,__ in grp]
g.rows = [['S1'] + ['P' if i == 0 else '0' for i in range(len(g.headers)-1)]]
g.col_idx = {h: i+1 for i, h in enumerate(g.headers)}
result = g._get_active_acmg_criteria(0)
print('active:', result)
assert len(result) == 1
print('PASS')
"
```
Expected: `active: [('PVS1', 'pvs')]` then `PASS`

**Step 3: Commit**

```bash
git add excel_to_html_report.py
git commit -m "feat: add _get_active_acmg_criteria method"
```

---

### Task 5: Add `_clinical_summary_table_html` method

**Files:**
- Modify: `excel_to_html_report.py` — add method to `iSeqReportGenerator` after `_get_active_acmg_criteria`

**Step 1: Add method**

```python
def _clinical_summary_table_html(self, row_indices: list) -> str:
    """Compact summary table: one row per variant with classification badges."""
    rows_html = ""
    for row_idx in row_indices:
        gene      = self._val_n(row_idx, "GENE") or "-"
        hgvsc     = self._val_n(row_idx, "HGVSc") or "-"
        hgvsp     = self._val_n(row_idx, "HGVSp") or "-"
        clnsig    = self._val_n(row_idx, "CLNSIG") or ""
        clnrevstat= self._val_n(row_idx, "CLNREVSTAT") or ""
        cancervar = self._val_n(row_idx, "CancerVar and Evidence") or ""
        intervar  = self._val_n(row_idx, "InterVar_automated") or ""
        vaf_raw   = self._val_n(row_idx, "VAF") or "-"
        dp        = self._val_n(row_idx, "DP") or "-"

        vaf_display = vaf_raw
        try:
            vaf_num = float(vaf_raw)
            vaf_pct = vaf_num * 100 if vaf_num <= 1 else vaf_num
            vaf_display = f"{vaf_pct:.1f}%"
        except (ValueError, TypeError):
            pass

        hgvsc_short = hgvsc[:35] + "…" if len(hgvsc) > 35 else hgvsc
        hgvsp_short = hgvsp[:25] + "…" if len(hgvsp) > 25 else hgvsp

        rows_html += f"""
            <tr class="clinical-summary-row"
                onclick="scrollToCard('card-{row_idx}')">
                <td class="gene">{escape(gene)}</td>
                <td class="monospace" title="{escape(hgvsc)}">{escape(hgvsc_short)}</td>
                <td class="monospace" title="{escape(hgvsp)}">{escape(hgvsp_short)}</td>
                <td>{_clinvar_sig_badge(clnsig)}</td>
                <td>{clnrevstat_to_stars(clnrevstat)}</td>
                <td>{_cancervar_tier_badge(cancervar)}</td>
                <td>{_intervar_badge(intervar)}</td>
                <td>{escape(vaf_display)}</td>
                <td>{escape(dp)}</td>
            </tr>"""

    return f"""
        <table class="clinical-summary-table">
            <thead>
                <tr>
                    <th>Gene</th><th>HGVSc</th><th>HGVSp</th>
                    <th>ClinVar</th><th>★</th>
                    <th>CancerVar</th><th>InterVar</th>
                    <th>VAF</th><th>DP</th>
                </tr>
            </thead>
            <tbody>{rows_html}
            </tbody>
        </table>"""
```

**Step 2: Verify import**

```bash
python3 -c "from excel_to_html_report import iSeqReportGenerator; print('OK')"
```
Expected: `OK`

**Step 3: Commit**

```bash
git add excel_to_html_report.py
git commit -m "feat: add _clinical_summary_table_html method"
```

---

### Task 6: Add `_variant_detail_card_html` method

**Files:**
- Modify: `excel_to_html_report.py` — add method after `_clinical_summary_table_html`

**Step 1: Add method**

```python
def _variant_detail_card_html(self, row_idx: int,
                               sample_name: str, safe_sample: str) -> str:
    """Collapsible clinical detail card for one variant."""
    gene      = self._val_n(row_idx, "GENE") or "Unknown"
    hgvsc     = self._val_n(row_idx, "HGVSc") or "-"
    hgvsp     = self._val_n(row_idx, "HGVSp") or "-"
    chrom     = self._val_n(row_idx, "Chr") or "-"
    pos       = self._val_n(row_idx, "Pos") or "-"
    clnsig    = self._val_n(row_idx, "CLNSIG") or ""
    clnrevstat= self._val_n(row_idx, "CLNREVSTAT") or ""
    clndn     = self._val_n(row_idx, "CLNDN") or ""
    cancervar = self._val_n(row_idx, "CancerVar and Evidence") or ""
    cosmic    = self._val_n(row_idx, "cosmic91") or ""
    gnomad_af = self._val_n(row_idx, "gnomad41_genome_AF") or ""
    vaf_raw   = self._val_n(row_idx, "VAF") or "-"
    dp        = self._val_n(row_idx, "DP") or "-"

    vaf_display = vaf_raw
    try:
        vaf_num = float(vaf_raw)
        vaf_pct = vaf_num * 100 if vaf_num <= 1 else vaf_num
        vaf_display = f"{vaf_pct:.1f}%"
    except (ValueError, TypeError):
        pass

    # ACMG active criteria chips
    active_acmg = self._get_active_acmg_criteria(row_idx)
    if active_acmg:
        acmg_chips = "".join(
            f'<span class="acmg-chip acmg-{css}">{label}</span>'
            for label, css in active_acmg
        )
    else:
        acmg_chips = ('<span style="color:var(--text-muted);'
                      'font-style:italic;">None met</span>')

    # IGV screenshot (relative path from samples/ directory)
    igv_path = self.find_igv_screenshot(sample_name, chrom, pos)
    igv_html = ""
    if igv_path:
        samples_dir = (self.output_dir / "samples").resolve()
        rel_igv = os.path.relpath(igv_path, str(samples_dir))
        igv_html = (f'<img src="{rel_igv}" '
                    f'alt="IGV {escape(gene)} {escape(chrom)}:{escape(pos)}" '
                    f'class="igv-image" style="max-width:100%;margin-top:10px;"'
                    f' onerror="this.style.display=\'none\'">')

    # Optional detail rows
    disease_html = ""
    if clndn and clndn not in (".", "-"):
        disease_html = (f'<div class="card-detail-row">'
                        f'<span class="card-detail-label">ClinVar disease:</span>'
                        f' <span>{escape(clndn)}</span></div>')

    gnomad_html = ""
    if gnomad_af and gnomad_af not in (".", "-"):
        gnomad_html = (f'<div class="card-detail-row">'
                       f'<span class="card-detail-label">gnomAD41 genome AF:</span>'
                       f' <span class="monospace">{escape(gnomad_af)}</span></div>')

    cosmic_html = ""
    if cosmic and cosmic not in (".", "-"):
        cosmic_html = (f'<div class="card-detail-row">'
                       f'<span class="card-detail-label">COSMIC ID:</span>'
                       f' <span class="monospace">'
                       f'{self._format_data_value("cosmic91", cosmic)}'
                       f'</span></div>')

    detail_url = f"variants/{safe_sample}_var{row_idx}.html"
    hgvsp_html = (f' <span class="card-hgvsp monospace">{escape(hgvsp)}</span>'
                  if hgvsp and hgvsp != "-" else "")

    return f"""
        <div class="variant-detail-card" id="card-{row_idx}">
            <div class="variant-detail-card-header" onclick="toggleCard(this)">
                <div class="card-header-left">
                    <span class="card-gene">{escape(gene)}</span>
                    <span class="card-hgvs monospace">{escape(hgvsc)}</span>
                    {hgvsp_html}
                </div>
                <div class="card-header-right">
                    {_clinvar_sig_badge(clnsig)}
                    {clnrevstat_to_stars(clnrevstat)}
                    {_cancervar_tier_badge(cancervar)}
                    <span class="card-vaf">VAF: {escape(vaf_display)} · DP: {escape(dp)}</span>
                    <span class="card-toggle">&#9662;</span>
                </div>
            </div>
            <div class="variant-detail-card-body">
                {disease_html}
                <div class="card-detail-row">
                    <span class="card-detail-label">ACMG active criteria:</span>
                    <span class="acmg-chips-inline">{acmg_chips}</span>
                </div>
                {gnomad_html}
                {cosmic_html}
                {igv_html}
                <div class="card-detail-row" style="margin-top:14px;">
                    <a href="{detail_url}" class="detail-link">Full Annotation ›</a>
                </div>
            </div>
        </div>"""
```

**Step 2: Verify import**

```bash
python3 -c "from excel_to_html_report import iSeqReportGenerator; print('OK')"
```

**Step 3: Commit**

```bash
git add excel_to_html_report.py
git commit -m "feat: add _variant_detail_card_html method"
```

---

### Task 7: Modify `generate_sample_page()` to use tabs

**Files:**
- Modify: `excel_to_html_report.py` — `generate_sample_page()` method (~line 815)

**Step 1: Replace the section after the stats cards block.**

The current code builds the stats section then immediately appends the variant table.
Replace from the variant table onwards (after `</div>` closing the dashboard-stats) with:

```python
        # ── Tab bar ──────────────────────────────────────────────
        html += '''
        <div class="tab-bar">
            <button class="tab-btn active" data-tab="tab-clinical"
                    onclick="switchTab('tab-clinical')">
                &#10003; Clinical Summary
            </button>
            <button class="tab-btn" data-tab="tab-full"
                    onclick="switchTab('tab-full')">
                Full Annotation
            </button>
        </div>

        <!-- Clinical Summary tab -->
        <div id="tab-clinical" class="tab-pane active">
        '''

        # Summary table
        html += self._clinical_summary_table_html(row_indices)

        # Detail cards (all expanded if <=3, collapsed if >3)
        collapse_by_default = len(row_indices) > 3
        for row_idx in row_indices:
            card_html = self._variant_detail_card_html(row_idx, sample_name, safe_sample)
            if collapse_by_default:
                card_html = card_html.replace(
                    'class="variant-detail-card"',
                    'class="variant-detail-card collapsed"', 1)
            html += card_html

        html += '</div>\n'

        # ── Full Annotation tab (existing variant table) ──────────
        html += '<div id="tab-full" class="tab-pane">\n'
        html += f'''
        <table class="variant-table">
            <thead>
                <tr>
                    <th>#</th>
                    <th>Gene</th>
                    <th>Variant</th>
                    <th>HGVSc</th>
                    <th>HGVSp</th>
                    <th>VAF</th>
                    <th>DP</th>
                    <th>Action</th>
                </tr>
            </thead>
            <tbody>'''

        for i, row_idx in enumerate(row_indices):
            # ... (existing per-row logic unchanged — gene, hgvsc, vaf bar etc.)
            # copy the existing loop body here verbatim
```

> **Note:** The existing per-row loop body (lines ~872–910) is moved inside the Full Annotation tab div, verbatim. The closing `</table></div></div></body></html>` structure becomes:
> ```html
> </tbody></table>    ← closes Full Annotation table
> </div>              ← closes tab-full pane
> </div>              ← closes container
> </body></html>
> ```

Also add `<script>{get_javascript()}</script>` to the `<head>` in `generate_sample_page` (it is currently only added in `generate_variant_page`).

**Step 2: Run a dry smoke test against TestData**

If the TestData pipeline output exists at `/data/alvin/hg38annotate/TestData/`:
```bash
python3 /data/alvin/hg38annotate/excel_to_html_report.py \
    /data/alvin/hg38annotate/TestData/output/Combine.xlsx \
    /tmp/html_test \
    /data/alvin/hg38annotate/TestData/output/SnapShots 2>&1 | tail -20
```
Expected: `HTML reports generated in: /tmp/html_test` — no tracebacks.

**Step 3: Visual check**

Open `/tmp/html_test/samples/*.html` in a browser (or use `python3 -m http.server 8080 --directory /tmp/html_test`).

Verify:
- [ ] Page opens on Clinical Summary tab by default
- [ ] Summary table shows gene, HGVSc/p, ClinVar badge, stars, CancerVar badge, InterVar badge, VAF, DP
- [ ] Clicking a row scrolls to + expands the detail card
- [ ] Each detail card shows disease name (if available), active ACMG chips, gnomAD AF, COSMIC ID, IGV screenshot
- [ ] "Full Annotation ›" link in the card opens the variant detail page correctly
- [ ] Clicking Full Annotation tab shows the original variant table
- [ ] Clicking Clinical Summary tab returns to the clinical view

**Step 4: Commit**

```bash
git add excel_to_html_report.py
git commit -m "feat: add Clinical Summary / Full Annotation tabs to sample HTML report"
```

---

### Task 8: Push and update TODO

**Step 1: Push to GitHub**

```bash
git push origin main
```

**Step 2: Update `tasks/todo.md`**

Move "Improve HTML report — tabbed clinical view" to Completed section.

**Step 3: Commit TODO**

```bash
git add tasks/todo.md
git commit -m "chore: mark clinical HTML report tabs as complete"
git push origin main
```

---

## Testing Checklist

- [ ] All 15 unit tests pass: `python3 -m pytest tests/test_html_helpers.py -v`
- [ ] `python3 -c "from excel_to_html_report import get_css_styles, get_javascript; print('OK')"` — no error
- [ ] Sample HTML opens on Clinical Summary tab
- [ ] Summary table has correct columns and coloured badges
- [ ] Stars reflect CLNREVSTAT correctly
- [ ] Active ACMG chips shown (inactive criteria hidden in clinical tab)
- [ ] Cards collapse/expand on click
- [ ] Row click scrolls to correct card
- [ ] IGV screenshots embedded where present
- [ ] Full Annotation tab shows original variant table unchanged
- [ ] "Full Annotation ›" links work
