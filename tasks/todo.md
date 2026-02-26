# TODO

## Pending

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

## Completed

- [x] IGV 2.19.7 + Java 21 fix (`openjdk-21-jre` for `libawt_xawt.so`)
- [x] VEP column shift fix (`hg38.fa.index` pre-created; added to Databases.tar.gz)
- [x] `check_docker_deps.sh` — added `hg38.fa.index` existence check
- [x] `filter_anno_iseq()` column fix — `$23/$25` → `$22/$24` (cytoBand/STRAND were wrong columns)
- [x] DB_BASE path unification across all scripts
- [x] TransVar databases moved out of Docker image into DB_BASE/transvar/
- [x] Software.tar.gz rebuilt (removed obsolete annovar/ and CancerVar/)
- [x] Databases.tar.gz created with hg38.fa.index included
- [x] README updated for IGV 2.19.7, Java 21, setup steps
