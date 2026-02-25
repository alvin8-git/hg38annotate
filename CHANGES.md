# CHANGES — hg38annotate

## Unreleased (main)

### 2026-02 — IGV 2.19.7 upgrade; offline genome loading; remove Java 8

**`Dockerfile`**

- Upgraded IGV from 2.3.81 (2016) to 2.19.7 (October 2025). IGV 2.19.7
  requires Java 11, which is already installed as `openjdk-11-jre-headless`.
- Removed `openjdk-8-jre-headless` — no longer needed.
- Moved IGV download layer to after the VEP INSTALL.pl layer so that future
  IGV-only upgrades do not bust the expensive VEP cache.

**`processVCF-hg38.sh`**

- Changed `-g hg38` to `-g "$hg38_fasta"` (`$HG38_FASTA` env var, default
  `$DB_BASE/GRCh38/hg38.fa`). Passing the local FASTA path instead of the
  genome name prevents IGV from querying Broad's online genome server at
  startup — the main source of per-sample delay. No GTF or cytoband file is
  needed; `hg38.fa` + `hg38.fa.fai` alone suffice for read pile-up snapshots.
- Removed `-java "$java8_path"` from the IGV call; IGV 2.19.7 uses the system
  `java` (Java 11).
- Updated `igv_jar` default path to `IGV_2.19.7/igv.jar`.
- Removed `java8_path` variable and the Java 8 availability check.

**`make_IGV_snapshots.py`**

- Default `java_path` changed from the Java 8 absolute path to `java`.
- Default `igv_jar_bin` updated to `bin/IGV_2.19.7/igv.jar`.

**`check_docker_deps.sh`**

- Replaced the Java 8 FAIL check with a Java 11+ check (FAIL if not present).
- Updated `IGV_JAR` default to `IGV_2.19.7/igv.jar`.
- Updated IGV functional test to use `java` (not `$JAVA8`).

---

### 2026-02 — TransVar databases moved out of Docker image

**`Dockerfile`**

- Removed `transvar config --download_anno --refversion hg38` build step (~236 MB, ~2 minutes).
  TransVar annotation databases (refseq, ccds, ensembl, gencode, ucsc) are now distributed
  as part of `Databases.tar.gz` and mounted at runtime under `$DB_BASE/transvar/`.
- Build time reduced by ~2 minutes; image size reduced by ~230 MB.

**`entrypoint.sh`**

- Added TransVar config generation at container startup. `~/.transvar.cfg` is written from
  the current `$DB_BASE` value before privilege drop, so the config is correct whether
  `DB_BASE` is the default or overridden at runtime with `-e DB_BASE=…`.

**`check_docker_deps.sh`**

- Added `$DB_BASE/transvar` to section 10 database directory checks.

---

### 2026-02 — VEP 115 cache upgrade

**`mergeVCFannotation-optimized-hg38.sh`**

- Added `--cache_version 115` to the VEP command, switching from the VEP 105 RefSeq cache
  (`105_GRCh38`, RefSeq 2021-05, GENCODE 39, gnomAD r2.1.1, ClinVar 202106, COSMIC 92)
  to the VEP 115 RefSeq cache
  (`115_GRCh38`, RefSeq August 2024, GENCODE 49, GRCh38.p14, gnomAD v4.1, ClinVar 202502, COSMIC 101).

  VEP 105 software reads the 115 cache correctly via `--cache_version 115`. Output column
  headers are **100% identical** to the VEP 105 cache — no downstream parsing changes required.

  Data changes on TestData (27 variants, 5 samples):
  - **Consequence field**: unchanged for all 27 variants; filter output unchanged (10 variants).
  - **ClinVar** (202502 vs 202106): updated for 9 variants — TP53 intronic variants gained
    `benign`; KRAS G12D added `not_provided,association`; TP53 Cys135Ser lost `likely_pathogenic`.
  - **SIFT**: updated scores for KRAS G12D (`deleterious(0)` → `deleterious_low_confidence(0.04)`),
    TP53 Pro72Arg, MPL Trp515Leu.
  - **PolyPhen**: lost for KRAS G12D and TP53 Cys135Ser (transcript model change in RefSeq update).
  - **PubMed**: 10–80 additional references per variant (more recent literature indexed).
  - **Variant IDs**: new rsID (`rs2141510626`) and COSV IDs for KRAS, JAK2, CEBPA variants.
  - **gnomAD_AF in VEP output**: empty for 10 variants (v115 cache uses renamed `gnomADe_*`
    columns that VEP 105 software cannot map to its output schema). This does NOT affect the
    final Excel output — gnomAD 4.1 allele frequencies are provided by annovar-fast in dedicated
    `gnomad41_exome_AF` / `gnomad41_genome_AF` columns independently.

---

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
