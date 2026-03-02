# Clinical HTML Report — Design Document

**Date:** 2026-03-02
**Status:** Approved
**Scope:** `excel_to_html_report.py` only — no shell scripts, no new data sources

---

## Problem

The existing per-sample HTML report exposes all annotation data (population frequencies,
prediction scores, raw ACMG criteria grid) in a single flat view. Clinical scientists
need to quickly assess variant classifications without wading through 150+ columns.

## Goal

Add a **Clinical Summary tab** as the default view in each `{sample}.html` report,
presenting a compact variant table and per-variant interpretation cards. The existing
full annotation view is preserved unchanged as a second tab.

---

## Design

### Tab structure

Each `{sample}.html` gets a tab bar immediately below the header:

```
[ Clinical Summary ▼ ]  [ Full Annotation ]
```

- **Clinical Summary** is the default active tab (opens first on load)
- **Full Annotation** tab contains the existing content exactly as-is
- Tab switching: pure JS — two `<div>` blocks, toggle `display: none`
- `Summary.html` unchanged; still links to `{sample}.html`

---

### Clinical Summary tab — Part A: Summary table

One row per filtered variant:

| Gene | HGVSc | HGVSp | ClinVar | ★ | CancerVar | InterVar | VAF | DP |
|------|-------|-------|---------|---|-----------|----------|-----|----|

- **ClinVar** cell: coloured badge
  - Pathogenic → red (`--pathogenic-color`)
  - Likely pathogenic → orange (`--likely-pathogenic-color`)
  - VUS → grey (`--vus-color`)
  - Likely benign → teal (`--likely-benign-color`)
  - Benign → green (`--benign-color`)
- **★ column**: 0–4 stars from `CLNREVSTAT` (see mapping below)
- **CancerVar** cell: coloured badge using existing tier colours
- **InterVar** cell: coloured badge from `InterVar_automated`
- Row click: scrolls to that variant's detail card

---

### Clinical Summary tab — Part B: Per-variant detail cards

One collapsible card per variant below the summary table.

**Default expand state:** all expanded if ≤ 3 variants; all collapsed if > 3.

**Card layout:**
```
┌─ GENE  HGVSc · HGVSp  [ClinVar badge] [★★★] [CancerVar badge]  VAF: 45% · DP: 312 ─┐
│  ClinVar disease:  Myeloproliferative neoplasm (CLNDN)                                 │
│  ACMG active criteria:  [PS1] [PM2] [PP3]                                              │
│  gnomAD41 genome AF:  0.000012                                                         │
│  COSMIC ID:  COSV12345                                                                 │
│  [IGV screenshot — if available]                                                       │
└────────────────────────────────────────────────────────────────────────────────────────┘
```

**Active ACMG criteria**: only criteria where column value is not `.` / empty / `0`.
Full ACMG grid remains available in the Full Annotation tab.

---

### CLNREVSTAT → star rating mapping

| CLNREVSTAT value | Display |
|------------------|---------|
| `practice_guideline` | ★★★★ |
| `reviewed_by_expert_panel` | ★★★ |
| `criteria_provided,_multiple_submitters,_no_conflicts` | ★★ |
| `criteria_provided,_single_submitter` | ★ |
| `no_assertion_criteria_provided` / `no_assertion_provided` | ☆ |
| `conflicting_interpretations_of_pathogenicity` | ⚠ conflict |

---

## Implementation scope

Only `excel_to_html_report.py` is modified.

| Function | Change |
|----------|--------|
| `get_css_styles()` | Add tab bar + card + star colour styles |
| `clnrevstat_to_stars(val)` | New helper: CLNREVSTAT string → star HTML |
| `get_active_acmg(row, col_map)` | New helper: returns list of criteria with evidence |
| `build_clinical_summary_table(variants, col_map)` | New: compact summary table HTML |
| `build_variant_detail_cards(variants, col_map, snapshot_dir)` | New: collapsible cards HTML |
| `generate_sample_html(...)` | Modified: wraps existing content in Full Annotation tab, prepends Clinical tab + JS switcher |

---

## Out of scope (deferred)

- COSMIC Cancer Gene Census role/tier column (oncogene/TSG) — see `tasks/todo.md`
- New data source lookups (ClinVar API, Ensembl API)
- PDF export
- Summary.html clinical view
