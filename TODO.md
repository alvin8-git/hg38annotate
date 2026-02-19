# TODO - HG38 Annotation Pipeline

## Completed

### Docker Image
- [x] Add `pysam` and `cyvcf2` to Dockerfile
- [x] Fix CancerVar `config.ini` paths (`/home/alvin` -> `/home/user`)
- [x] Remove old CancerVar from Dockerfile (replaced by cancervar-fast)
- [x] Add `ANNOVAR_FAST` and `CANCERVAR_FAST` env vars to Dockerfile
- [x] Mount annovar-fast and humandb-tbi into container at runtime
- [x] Fix humandb-tbi mount: create `humandb-tbi -> ../humandb-tbi` symlink in annovar-fast dir

### annovar-fast Integration
- [x] Replace ANNOVAR with annovar-fast in `mergeVCFannotation-optimized-hg38.sh`
- [x] Replace CancerVar with cancervar-fast in `mergeVCFannotation-optimized-hg38.sh`
- [x] Remove Allsort.vcf generation (cancervar-fast reads Merge.vcf directly)
- [x] Test annovar-fast + cancervar-fast on TestData (8 variants, all passed)
- [x] Verify output format compatibility (col 14 CancerVar, col 42 cosmic91)

### Pipeline Testing
- [x] Full annotation stage tested in Docker — completed in 33s (vs 79s previously)
- [x] Test IGV snapshot stage
- [x] Test HTML report stage

### HTML Report Fixes
- [x] Fix `--summary` flag: `excel_to_html_report.py` did not handle `--summary <dir>` mode
- [x] Fix column offset for per-sample xlsx (no SAMPLE col → prepend synthetic SAMPLE col)
- [x] Fix IGV screenshots: pass `SnapShots/` as 3rd arg to HTML script
- [x] Fix stale `chr9.html` in Summary.html: `rm -rf html_reports` before regenerating

---

## Bugs

### HTML Report: ACMG / ClinVar / Predictions columns off by 2
**Priority: High** — ACMG criteria chips and computational predictions panels show wrong data.

Combine.xlsx has 150 columns. The hardcoded indices in `excel_to_html_report.py` are 2 positions too high:

| Item | Script | Actual (Combine.xlsx) |
|------|--------|----------------------|
| `population_freq` group end | col 88 (includes PVS1!) | col 86 (nci60) |
| `acmg_criteria` group start | col 89 (PS1) | col 87 (InterVar_automated) |
| `acmg_criteria` group end | col 122 (REVEL) | col 120 (CLNSIG) |
| ACMG_GROUPS PVS1 | col 90 | col 88 |
| ACMG_GROUPS PS1–PS4 | cols 91–94 | cols 89–92 |
| CLINVAR_COLS | [118–122] | [116–120] |
| PREDICTION_SCORES M-CAP | col 123 | col 121 |
| PREDICTION_SCORES REVEL | col 124 | col 122 |
| PREDICTION_SCORES SIFT | col 125/126 | col 123/124 |

Fix: subtract 2 from all `ACMG_GROUPS`, `CLINVAR_COLS`, and `PREDICTION_SCORES` indices,
and update `COLUMN_GROUPS["population_freq"]`, `["acmg_criteria"]`, and `["computational"]`.

Long-term fix: replace hardcoded column indices with header-name lookup so the report
is resilient to future column additions.

### HTML Report: Summary.html missing samples with 0 variants
**Priority: Medium** — Samples with no filtered variants produce no `samples/*.html` page
(since `self.samples` is empty), so they are absent from Summary.html.

Example: iSeq-001-S01_S81, S03, S04 have 0 variants after filtering → only iSeq-001-S02_S82
appears in Summary.html.

Fix: always write a `samples/{sample}.html` page even for 0-variant samples, showing a
"No filtered variants" message.

### HTML Report: `index.html` overwritten on each sample
**Priority: Low** — Each call to `python3 excel_to_html_report.py <sample.xlsx> html_reports`
overwrites `html_reports/index.html`. After 4 samples the file only reflects the last sample.

Fix: either rename per-run index to `{sample_name}_index.html`, or remove the `index.html`
generation for per-sample mode (Summary.html serves as the top-level landing page).

---

## Improvements

### HTML Report
- [ ] Switch ACMG/ClinVar/predictions from hardcoded column indices to header-name lookup
- [ ] Show 0-variant samples in Summary.html with a "No variants" badge
- [ ] Display CancerVar tier prominently on variant detail pages (highlighted badge)
- [ ] Add VAF frequency bar visualisation on sample variant table
- [ ] Link cosmic91 IDs to COSMIC database URLs
- [ ] Link ClinVar IDs to ClinVar web URLs

### Pipeline
- [ ] Add gnomAD_genome column name normalisation in `mergeVCFannotation-optimized-hg38.sh`
  (output uses `gnomad41_genome_AF`; ensure cancervar-fast config column names match)
- [ ] Add `--dry-run` flag to `processVCF-hg38.sh` to preview what would run
- [ ] Surface annotation warnings/errors more clearly in the run log

### Docker
- [ ] Publish image to Docker Hub or GitHub Container Registry (`ghcr.io`)
- [ ] Add `HEALTHCHECK` to Dockerfile
- [ ] Pin Python package versions in Dockerfile (`pip install transvar==x.y.z ...`)

---

## Release

- [ ] Create GitHub release `v1.0.0`
  - Tag commit: `git tag -a v1.0.0 -m "Initial release"`
  - Upload `Software.tar.gz` as release asset (annovar, snpEff, ensembl-vep)
  - Update README download URL from placeholder to actual release URL

---

## Testing / CI

- [ ] Add GitHub Actions workflow to validate `docker build` on push
- [ ] Add smoke test: run annotation stage on TestData inside Docker and assert expected
  output files exist (`Combine.xlsx`, `iSeq-001-S02_S82.xlsx`, etc.)
- [ ] Test with real clinical samples (non-TestData VCFs) to verify all annotation columns
