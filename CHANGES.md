# CHANGES — hg38annotate

## Unreleased (main)

### 2026-02 — IGV sort-by-base fix

**`make_IGV_snapshots.py`**

- Fixed `sort base` in `write_batchscript_regions()` to pass the explicit variant position:
  `sort base {chrom}:{pos}`. In IGV 2.3.81 batch mode, `sort base` without a locus argument
  sorts at an unreliable view-center position and reads appear in default genomic order
  in the snapshot. Passing the explicit position groups alt vs ref reads correctly at the
  variant site.

---

### 2026-02 — IGV timeout and HTML population frequency improvements

**`processVCF-hg38.sh`**

- Added `timeout 300` (5 minutes) around each IGV call in `process_single_igv_sample()`.
  When multiple IGV instances run in parallel, one can get stuck waiting on a network
  fetch; the timeout ensures that sample is skipped (exit code 124 logged as "[IGV] Timed
  out after 5 minutes for \<sample\> (skipping)") rather than blocking GNU parallel and
  preventing the HTML stage from running.

**`excel_to_html_report.py`**

- Added `AF_SEA`, `AF_NEA`, `AF_SAS` (GenomeAsia) to `COLUMN_GROUP_NAMES["population_freq"]`;
  these were absent so GenomeAsia frequencies never appeared in variant detail pages even
  when values were present in the xlsx.
- Added `POPULATION_FREQ_LABELS` dict mapping raw column names to source-prefixed display
  labels: `SG10K_AF_All`, `SG10K_AF_CHS`, `SG10K_AF_INS`, `SG10K_AF_MAS`,
  `GenomeAsia_AF_SEA`, `GenomeAsia_AF_NEA`, `GenomeAsia_AF_SAS`.
- `_pop_freq_html()` now resolves the display label via
  `POPULATION_FREQ_LABELS.get(col_name, col_name)` so the source database is unambiguous.

---

### 2026-02 — SG10K and genomeAsia tabix lookup fix

**`mergeVCFannotation-optimized-hg38.sh`**

- Fixed `SG10K_DB` default path: `$DATABASES_DIR/hg38annotate/SG10K.genes.txt.gz`
  (old path pointed to a non-existent directory).
- Fixed `GENOMEASIA_DB` default path: `$DATABASES_DIR/hg38annotate/genomeAsia.All.hg38.txt.gz`
  (old path pointed to a non-existent directory).
- Rewrote `run_sg10k()` to use `tabix` for per-variant lookup instead of a full-file
  awk join. Strips `chr` prefix before querying (database uses bare chromosome numbers).
  Output columns: `CHR POS REF ALT AF_All AF_CHS AF_INS AF_MAS`.
- Rewrote `run_genomeasia()` similarly. Output columns: `CHR POS REF ALT AF_SEA AF_NEA AF_SAS`.
- Fixed `cols_by_name` column names for genomeAsia in `combine_annotations()`:
  `SEA_AF/NEA_AF/SAS_AF` → `AF_SEA/AF_NEA/AF_SAS` (matching actual file header).
- Validated: AF values populated for matching SNPs, `.` for indels/absent variants.
  Both lookups complete in < 1 second for TestData (27 variants).

### 2026-02 — Header-name column lookup in annotation combiner

**`mergeVCFannotation-optimized-hg38.sh`**

- Added `cols_by_name FILE COL [COL …]` helper function that resolves column positions
  from the file header at runtime instead of relying on hardcoded `cut -f<N>` offsets.
  Leading/trailing whitespace is stripped from header values before matching so columns
  with embedded spaces (e.g. CancerVar output) work correctly.
- Rewrote `combine_annotations()` to use `cols_by_name` for all annotation inputs
  (annovar, snpEff, transvar, CancerVar, VEP, SG10K, genomeAsia). The combined output
  is now resilient to column additions or reordering in upstream tool outputs. The
  `compare.txt` input retains position-based cut because its column names are
  dynamically determined by the comparison databases in use.
- Added `verify_annovar_columns()` that checks expected gnomAD column names
  (`gnomad41_genome_AF`, `gnomad41_exome_AF`, etc.) in the annovar output header after
  each ANNOVAR-fast run and logs a warning if any are missing.
- VEP: stderr now redirected to `$sample.vep.log`; errors/fatals are surfaced via
  `log_warn` after completion; log file is removed on success.
- snpEff: all java and vcf-sort stderr redirected to `$sample.snpEff.log`; errors and
  JVM exceptions are surfaced via `log_warn` after completion.

**`processVCF-hg38.sh`**

- Added `log_warn()` helper (was absent from the main orchestrator).
- Added `--dry-run` / `-n` flag: previews which stages would run, be skipped (already
  complete), or be blocked (annotation not finished) without executing any pipeline code.

---

### 2026-02 — HTML report improvements

**`excel_to_html_report.py`**

- **CancerVar tier badge** — `_cancervar_tier_badge()` parses Tier I–IV from the
  `CancerVar and Evidence` column and renders a coloured badge in the gene-hero section
  of each variant detail page.
- **VAF frequency bar** — a 4 px mini-bar proportional to VAF % is shown below the VAF
  value in the per-sample variant table (`.vaf-bar-mini` / `.vaf-bar-mini-fill` CSS).
- **0-variant samples in Summary.html** — samples with no filtered variants receive a
  grey card header with a "No variants" pill badge (`.no-variants` CSS class).
- **COSMIC ID links** — `cosmic91` values matching `COSM\d+` in the data grid are
  hyperlinked to `cancer.sanger.ac.uk/cosmic/mutation/overview?id=<N>`.
- **ClinVar ID links** — `CLNALLELEID` values in the ACMG section are hyperlinked to
  `ncbi.nlm.nih.gov/clinvar/variation/<id>/`.

---

### 2026-02 — Docker, pipeline and HTML fixes

**Docker / file ownership**

- Entrypoint now detects rootless Docker via `/proc/self/uid_map` (col2 ≠ 0 on row 1).
  In rootless mode it stays as root (= host user on disk) and skips `chown`. In standard
  Docker it remaps the internal `user` account to `HOST_UID`/`HOST_GID` and uses `gosu`.
  Only `output/` and `vcf/annotation/` are created/chowned — never a recursive chown on
  the entire `/data` mount.

**Pipeline stage tracking**

- `process_iseq()` guard changed from `if [ ! -d ./annotation ]` to
  `if [ ! -f ./annotation/Combine.xlsx ]` so the file-move step is not skipped when the
  entrypoint pre-creates the empty `/data/vcf/annotation` directory.
- `check_html_complete()` now checks for `Summary.html` directly instead of requiring
  more than one HTML file in `html_reports/`.

**HTML report — Summary.html landing page**

- Removed `index.html` generation; `Summary.html` is now the sole landing page.
- Fixed breadcrumb links in sample pages (`../index.html` → `../Summary.html`) and in
  variant detail pages (`../../index.html` → `../../Summary.html`).
- Added per-sample variant count and a Total Variants summary stat to Summary.html.

**HTML report — column lookup**

- Replaced all hardcoded 1-based column indices with header-name lookup
  (`self.col_idx` dict + `_col()`, `_cols()`, `_val_n()` helpers) so the report is
  resilient to column additions in either per-sample (149-col) or Combine (150-col) xlsx.

---

### 2025 — Initial pipeline

- annovar-fast + cancervar-fast integration (replaces legacy ANNOVAR + CancerVar).
- Parallel annotation: annovar-fast, VEP, snpEff, TransVar run concurrently; CancerVar,
  SG10K, GenomeAsia follow.
- Three-stage orchestration (`processVCF-hg38.sh`): Annotate → IGV snapshots → HTML.
- Headless IGV snapshots via xvfb-run, one PNG per filtered variant per sample.
- Interactive HTML reports with per-variant pages embedding IGV screenshots, ACMG
  criteria chips, ClinVar evidence, and pathogenicity prediction scores.
- Docker image with rootless and standard Docker support.
- TestData: 5 iSeq panel samples (S02, S12, S26, S32, S51).
