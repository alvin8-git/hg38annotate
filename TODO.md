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
- [x] Fix ACMG / ClinVar / Predictions columns off by 2 — replaced all hardcoded 1-based
  column indices with header-name lookup (`self.col_idx` dict + `_col()`, `_cols()`, `_val_n()`)
  so report is resilient to column additions in either per-sample (149 col) or Combine (150 col) xlsx

### Docker / File Ownership
- [x] Fix container changing ownership of `/data` mount to unknown uid (166535/166536)
  Root cause: rootless Docker maps container `uid 0` → host user; old entrypoint did
  `chown -R user:user /data` (uid 1000 → host uid 166535). Fix: detect rootless mode via
  `/proc/self/uid_map` (NR==1 col2 ≠ 0), stay as root in rootless mode (= host user on disk),
  only chown `output/` and `vcf/annotation/` in standard Docker after remapping to HOST_UID/HOST_GID.

### Pipeline Stage Tracking
- [x] Fix annotation stage: `process_iseq()` skipped moving output files to `./annotation/`
  because the entrypoint pre-creates `/data/vcf/annotation` (empty directory). The guard
  `if [ ! -d ./annotation ]` was always false, leaving xlsx/txt files in `/data/vcf/` instead
  of `./annotation/`, so `check_annotation_complete()` found 0 xlsx files and IGV/HTML stages
  reported "Annotation not complete". Fix: changed guard to `if [ ! -f ./annotation/Combine.xlsx ]`
  to detect an empty pre-created directory vs a populated one. Validated with 5-sample TestData:
  all 3 stages now complete (annotation → 10 IGV snapshots → 5 HTML pages + Summary.html).
- [x] Fix `check_html_complete()` in `processVCF-hg38.sh`: was checking for `> 1` root-level
  HTML files (relied on both `index.html` + `Summary.html`). Now checks for `Summary.html`
  existence directly, since that is the sole root-level landing page.

### HTML Report Landing Page
- [x] Remove `index.html` generation — `generate_landing_page()` and its `index.html` write
  removed from `generate_reports()`; `Summary.html` is now the only landing page. Fixes the
  bug where each per-sample xlsx call overwrote `html_reports/index.html`.
- [x] Fix breadcrumb "All Samples" link in sample pages: `../index.html` → `../Summary.html`
- [x] Fix breadcrumb "All Samples" link in variant pages: `../../index.html` → `../../Summary.html`
- [x] Add per-sample variant count to Summary.html cards — counted from `variants/{sample}_var*.html`
  files; also added Total Variants stat to the Summary.html dashboard.

---

## Bugs

### HTML Report: Summary.html missing samples with 0 variants
**Priority: Medium** — Samples with no filtered variants produce no `samples/*.html` page
(since `self.samples` is empty), so they are absent from Summary.html.

Fix: always write a `samples/{sample}.html` page even for 0-variant samples, showing a
"No filtered variants" message.

---

## Improvements

### HTML Report
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
