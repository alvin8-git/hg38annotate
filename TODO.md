# TODO - HG38 Annotation Pipeline

## Docker Image
- [x] Add `pysam` and `cyvcf2` to Dockerfile
- [x] Fix CancerVar `config.ini` paths (`/home/alvin` -> `/home/user`)
- [x] Remove old CancerVar from Dockerfile (replaced by cancervar-fast)
- [x] Add `ANNOVAR_FAST` and `CANCERVAR_FAST` env vars to Dockerfile
- [x] Mount annovar-fast and humandb-tbi into container at runtime
- [x] Fix humandb-tbi mount: create `humandb-tbi -> ../humandb-tbi` symlink in annovar-fast dir

## annovar-fast Integration
- [x] Replace ANNOVAR with annovar-fast in `mergeVCFannotation-optimized-hg38.sh`
- [x] Replace CancerVar with cancervar-fast in `mergeVCFannotation-optimized-hg38.sh`
- [x] Remove Allsort.vcf generation (cancervar-fast reads Merge.vcf directly)
- [x] Test annovar-fast + cancervar-fast on TestData (8 variants, all passed)
- [x] Verify output format compatibility (col 14 CancerVar, col 42 cosmic91)

## Pipeline
- [x] Full annotation stage tested in Docker — completed in 33s (vs 79s previously)
- [x] Test IGV snapshot stage
- [x] Test HTML report stage (fixed --summary flag in excel_to_html_report.py)
