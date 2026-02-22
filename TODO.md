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
- [x] Fix IGV stage: `Combine.Filter.txt` (merged multi-sample VCF) was included in the
  per-sample IGV loop, producing a spurious "No BAM file found for Combine, skipping..."
  warning on every run. Filter-file loop in `generate_igv_snapshots()` now explicitly skips
  filenames `Combine` and `Merge`.

### Annotation Combiner Robustness
- [x] Replace hardcoded `cut -f<N>` column positions in `combine_annotations()` with
  `cols_by_name()` header-name lookup — new awk-based helper reads the file header at
  runtime and emits columns in the order listed, so the combined output is resilient to
  column additions or reordering in upstream tool outputs (annovar-fast, snpEff, transvar,
  CancerVar, VEP, SG10K, genomeAsia). Column names are now self-documenting in the source.
  `compare.txt` retains position-based cut (column names are run-specific).
  Validated end-to-end in Docker: all column names correct in xlsx output, 10 IGV
  snapshots and 5 HTML pages generated as expected.
- [x] Fix SG10K and genomeAsia database lookups:
  - Updated `SG10K_DB` default to `$DATABASES_DIR/hg38annotate/SG10K.genes.txt.gz`
    (was pointing to a non-existent path).
  - Updated `GENOMEASIA_DB` default to `$DATABASES_DIR/hg38annotate/genomeAsia.All.hg38.txt.gz`
    (was pointing to a non-existent path).
  - Rewrote `run_sg10k()` and `run_genomeasia()` to use `tabix` for fast per-variant lookup
    instead of slow full-file awk join. Chr prefix (`chr1` → `1`) stripped for tabix query.
  - Fixed genomeAsia column names in `cols_by_name` call: `SEA_AF/NEA_AF/SAS_AF` →
    `AF_SEA/AF_NEA/AF_SAS` (matching actual column names in the database file header).
  - Output headers now: SG10K `CHR POS REF ALT AF_All AF_CHS AF_INS AF_MAS`;
    genomeAsia `CHR POS REF ALT AF_SEA AF_NEA AF_SAS`.
  - Validated: AF values populated for matching SNPs, `.` for indels/absent variants.

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
- [x] Show 0-variant samples in Summary.html with a "No variants" badge — grey card header,
  pill badge in header, variant count in muted colour; uses `.no-variants` CSS class
- [x] Display CancerVar tier prominently on variant detail pages — `_cancervar_tier_badge()`
  parses Tier I/II/III/IV and renders a coloured badge in the gene-hero section
- [x] Add VAF frequency bar on sample variant table — 4 px mini-bar below the VAF % text,
  width proportional to VAF; new `.vaf-bar-mini` CSS classes
- [x] Link cosmic91 IDs to COSMIC database URLs — `_format_data_value()` in `_data_grid_html()`
  hyperlinks COSM\d+ IDs to `cancer.sanger.ac.uk/cosmic/mutation/overview?id=<N>`
- [x] Link ClinVar IDs to ClinVar web URLs — CLNALLELEID values in `_acmg_section_html()`
  linked to `ncbi.nlm.nih.gov/clinvar/variation/<id>/`

### Pipeline
- [x] Add gnomAD_genome column name normalisation in `mergeVCFannotation-optimized-hg38.sh`
  — `verify_annovar_columns()` checks expected gnomAD column names (`gnomad41_genome_AF` etc.)
  in the annovar output header and logs a warning if any are missing; added column-range
  comments to `combine_annotations()` documenting each `cut -f` block
- [x] Add `--dry-run` (`-n`) flag to `processVCF-hg38.sh` — previews which stages would run
  (or be skipped/blocked) without executing any of them
- [x] Surface annotation warnings/errors more clearly in the run log
  — VEP and snpEff now redirect stderr to per-run log files instead of `/dev/null`;
  after each tool completes the log is grepped for errors/exceptions and surfaced via
  `log_warn`; log file is removed on success. Added `log_warn` to `processVCF-hg38.sh`.

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
