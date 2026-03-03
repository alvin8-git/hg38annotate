# TODO

## Pending

### COSMIC Cancer Gene Census annotation
- Add static lookup table (~700 genes) to Databases with oncogene/TSG role + tier 1/2
- Add new column `CGC_Role` (oncogene/TSG/both) and `CGC_Tier` to annotation output
- Surface role in HTML clinical report detail blocks
- Deferred: keep to reorganising existing data first

### Upload release archives to GitHub Releases
- `Software.tar.gz` (232 MB) — contains `snpEff/` + `ensembl-vep/`
- `Databases.tar.gz` (1.2 GB) — contains `SG10k/`, `transvar/`, `genomeAsia/`, `snpEff/`, `GRCh38/hg38.fa.index`
- Requires manual upload via GitHub web UI or `gh release upload` with a token
- Both files are in `.gitignore`; distributed via GitHub Releases only

### IGV --force skips snapshots after annotation re-run
- When `--force` triggers full pipeline, annotation moves `*.Filter.txt` to `annotation/`
  before IGV stage runs → IGV stage reports "No filter files found"
- `create_output` copies files to `output/` but IGV reads from VCF dir
- Investigate: does IGV stage read from `output/` or VCF dir? Fix ordering or copy step.

### Verify IGV offline fix on zbolt-01 after rebuild
- Requires `docker build` to pick up `entrypoint.sh` (IGV prefs) + `make_IGV_snapshots.py` (sleep 2000) changes
- Expected: no `hg38.json` / `ncbiRefSeqSelect.txt.gz` network errors in IGV log
- Expected: no `ConcurrentModificationException` in IGV log
- Expected: PNG snapshots generated correctly

### Fix HUMANDB WARN on zbolt-01
- User sets `-e HUMANDB=/mnt/ssd/alvin/humandb-tbi` but doesn't mount the volume
- Fix: add `-v /mnt/ssd/alvin/humandb-tbi:/mnt/ssd/alvin/humandb-tbi:ro` to run command on zbolt-01
- Pipeline works despite the WARN (annovar-fast finds databases via other path), but clean dep check requires the mount

## Completed

- [x] Clinical HTML report — tabbed Clinical Summary / Full Annotation UI in `{sample}.html` (2026-03-03)
  - Badge helpers: `clnrevstat_to_stars`, `_clinvar_sig_badge`, `_intervar_badge`
  - CSS for tab bar, badges, star ratings, variant cards
  - JS: `switchTab`, `toggleCard`, `scrollToCard`
  - Methods: `_get_active_acmg_criteria`, `_clinical_summary_table_html`, `_variant_detail_card_html`
  - `generate_sample_page()` modified with tab structure; 45 unit tests

- [x] IGV offline fix — `entrypoint.sh` writes `prefs.properties` with `DEFAULT_GENOME_KEY` pointing to local FASTA; prevents startup online genome request
- [x] IGV `ConcurrentModificationException` fix — `sleep 2000` before each snapshot in batch script
- [x] IGV `-g genome` command-line flag — passes local FASTA to `igv.sh` at startup
- [x] cyvcf2 restored — removed prematurely; required by mounted `annovar-fast.py` and `cancervar-fast.py`
- [x] `.dockerignore` created — build context reduced from ~1.5 GB to ~220 KB
- [x] CentOS 7 JVM fix — `--security-opt seccomp=unconfined` in `run_docker.sh`; dpkg-divert ordering fixed in Dockerfile
- [x] `pip3 --prefer-binary` — forces manylinux wheels, avoids CentOS 7 compile failures
- [x] IGV 2.19.7 + Java 21 fix (`openjdk-21-jre` for `libawt_xawt.so`)
- [x] VEP column shift fix (`hg38.fa.index` pre-created; added to Databases.tar.gz)
- [x] `check_docker_deps.sh` — added `hg38.fa.index` existence check
- [x] `filter_anno_iseq()` column fix — `$23/$25` → `$22/$24` (cytoBand/STRAND were wrong columns)
- [x] DB_BASE path unification across all scripts
- [x] TransVar databases moved out of Docker image into DB_BASE/transvar/
- [x] Software.tar.gz rebuilt (removed obsolete annovar/ and CancerVar/)
- [x] Databases.tar.gz created with hg38.fa.index included
- [x] README updated for IGV 2.19.7, Java 21, setup steps
