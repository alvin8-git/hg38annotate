# hg38annotate

A Docker-based VCF annotation pipeline for the HG38/GRCh38 reference genome. Takes raw VCF files and produces multi-tool annotations, CancerVar cancer classification, IGV screenshots, and interactive HTML reports.

## Features

- **Multi-tool annotation** — VEP (Ensembl), snpEff, TransVar, annovar-fast, cancervar-fast run in parallel
- **Cancer classification** — CancerVar Tier I–IV scoring via cancervar-fast
- **Population databases** — SG10K, GenomeAsia, gnomAD, ExAC, ESP6500, 1000 Genomes
- **IGV screenshots** — Automated headless IGV snapshots for each filtered variant
- **Interactive HTML reports** — Per-sample variant pages with embedded IGV screenshots, ACMG chips, and prediction score tables
- **Stage control** — Run all three stages (Annotate → IGV → HTML) or individual stages; skip already-complete stages

## Prerequisites

- Docker ≥ 20.10 (rootless or standard)
- The annotation tools below (bundled in `Software.tar.gz` from the GitHub release)
- annovar-fast + humandb-tbi (tabix-indexed databases, mounted at runtime)
- HG38/GRCh38 reference databases (VEP cache, snpEff db, reference FASTA)

## Installation

### 1. Clone the repository

```bash
git clone git@github.com:alvin8-git/hg38annotate.git
cd hg38annotate
```

### 2. Download and extract annotation tools

The annotation tools (ANNOVAR, snpEff, VEP) are too large for git and are distributed as a release archive.

```bash
wget https://github.com/alvin8-git/hg38annotate/releases/download/v1.0.0/Software.tar.gz
tar -xzf Software.tar.gz
```

This extracts the following directories into the repo root (required for `docker build`):

```
annovar/          # ANNOVAR perl scripts (legacy, bundled in image)
snpEff/           # snpEff jar + scripts
ensembl-vep/      # VEP software (cache mounted at runtime)
```

> **annovar-fast** (the primary ANNOVAR replacement) and **humandb-tbi** (tabix-indexed databases) are mounted at runtime — see [Runtime Mounts](#runtime-mounts).

### 3. Build the Docker image

```bash
docker build -t hg38annotate:latest .
```

Build time: ~10 minutes (VEP module installation). Subsequent builds use cached layers.
Image size: ~2 GB (excluding mounted databases).

## Docker Run

### Interactive shell

```bash
docker run --rm -it \
    -e HOST_UID=$(id -u) \
    -e HOST_GID=$(id -g) \
    -v /path/to/Databases:/home/user/Databases:ro \
    -v /path/to/annovar-fast:/path/to/annovar-fast:ro \
    -v /path/to/humandb-tbi:/path/to/humandb-tbi:ro \
    -v /path/to/data:/data \
    hg38annotate:latest bash
```

### Run full pipeline

```bash
docker run --rm \
    -e HOST_UID=$(id -u) \
    -e HOST_GID=$(id -g) \
    -v /path/to/Databases:/home/user/Databases:ro \
    -v /path/to/annovar-fast:/path/to/annovar-fast:ro \
    -v /path/to/humandb-tbi:/path/to/humandb-tbi:ro \
    -v /path/to/data:/data \
    hg38annotate:latest bash -c "cd /data/vcf && processVCF-hg38.sh"
```

### Example `run_docker.sh`

The included `run_docker.sh` shows a working example for a local setup:

```bash
docker run --rm -it \
    -e HOST_UID=$(id -u) \
    -e HOST_GID=$(id -g) \
    -v /data/alvin/Databases:/home/user/Databases:ro \
    -v /data/alvin/hg38annotate/TestData:/data \
    -v /data/alvin/annovar/annovar-fast:/data/alvin/annovar/annovar-fast:ro \
    -v /data/alvin/annovar/humandb-tbi:/data/alvin/annovar/humandb-tbi:ro \
    hg38annotate:latest bash
```

### Runtime Mounts

| Host path | Container path | Description |
|-----------|---------------|-------------|
| `~/Databases` | `/home/user/Databases` | All HG38 reference databases (see below) |
| `/path/to/annovar-fast` | same path inside container | annovar-fast scripts + cancervar-fast |
| `/path/to/humandb-tbi` | same path inside container | Tabix-indexed ANNOVAR databases |
| `/path/to/data` | `/data` | Input VCF/BAM files and pipeline output |

> annovar-fast and humandb-tbi must be mounted at the **same absolute path** inside the container as on the host. The `ANNOVAR_FAST` and `CANCERVAR_FAST` environment variables in the Dockerfile point to the host paths.

#### Database directory layout (`~/Databases`)

| Path | Description |
|------|-------------|
| `Databases/GRCh38/hg38.fa` | GRCh38 reference FASTA |
| `Databases/vep/` | VEP GRCh38 RefSeq cache (~28 GB) |
| `Databases/snpEff/` | snpEff GRCh38.p13.RefSeq database |
| `Databases/SG10K.hg38.vcf/` | SG10K Singapore population (HG38) |
| `Databases/genomeAsia/` | GenomeAsia 100K database |

### File Ownership (Rootless Docker)

The entrypoint automatically detects whether Docker is running in **rootless mode** by reading `/proc/self/uid_map`:

- **Rootless Docker** — container `uid 0` maps to the host user. The pipeline runs as root inside the container, which is equivalent to running as the host user on disk. All output files are owned by the host user. No `-e HOST_UID` required (but harmless if passed).
- **Standard Docker** — the entrypoint remaps the internal `user` account to `HOST_UID`/`HOST_GID` (passed via `-e`), then drops privileges via `gosu`. Always pass `-e HOST_UID=$(id -u) -e HOST_GID=$(id -g)` in this mode to ensure correct file ownership.

The entrypoint **never** does a recursive `chown` on the entire `/data` mount — only the `output/` and `vcf/annotation/` subdirectories are created/owned if they don't exist.

## Testing

TestData with 5 iSeq panel VCF samples (VCF + BAM) is included in `TestData/`.

### Run the full pipeline on TestData

```bash
docker run --rm -it \
    -e HOST_UID=$(id -u) \
    -e HOST_GID=$(id -g) \
    -v /path/to/Databases:/home/user/Databases:ro \
    -v /path/to/annovar-fast:/path/to/annovar-fast:ro \
    -v /path/to/humandb-tbi:/path/to/humandb-tbi:ro \
    -v $(pwd)/TestData:/data \
    hg38annotate:latest bash -c "cd /data/vcf && bash /home/user/Scripts/processVCF-hg38.sh"
```

Expected results (total pipeline ~2 minutes):
- **Annotation stage**: ~33 seconds, produces `TestData/output/*.xlsx` (6 files: 5 per-sample + `Combine.xlsx`), 27 variants across 5 samples
- **IGV stage**: 10 PNG snapshots — one per filtered variant per sample (S02×1, S12×1, S26×3, S32×1, S51×4)
- **HTML stage**: `TestData/output/html_reports/Summary.html` + 5 sample pages + 10 per-variant detail pages with embedded IGV screenshots, ACMG chips, ClinVar, and prediction scores

### Run individual stages

```bash
# Inside the container (cd /data/vcf first)
processVCF-hg38.sh --annotate        # Annotation only
processVCF-hg38.sh --igv             # IGV snapshots only
processVCF-hg38.sh --html            # HTML reports only

processVCF-hg38.sh --from-igv        # IGV + HTML
processVCF-hg38.sh --from-html       # HTML only

processVCF-hg38.sh --html --force    # Force re-run HTML even if complete
processVCF-hg38.sh --status          # Check which stages are complete
```

### Verify tool installation

```bash
docker run --rm hg38annotate:latest /home/user/Scripts/check_docker_deps.sh
```

## Pipeline Overview

```
Input: VCF files in vcf/
         │
         ▼
┌─────────────────────────────────────────────┐
│  Stage 1: Annotation (~33s for 8 variants)  │
│                                             │
│  Merge VCFs ──► annovar-fast  ─┐            │
│                 VEP            ├──► Excel   │
│                 snpEff         │   (per     │
│                 TransVar       │   sample + │
│                 cancervar-fast ┘   Combine) │
└─────────────────────────────────────────────┘
         │
         ▼
┌──────────────────────────────────┐
│  Stage 2: IGV Snapshots          │
│                                  │
│  Filtered variants ──► BED files │
│  BAM + BED ──► xvfb + IGV ──► PNG│
└──────────────────────────────────┘
         │
         ▼
┌──────────────────────────────────────────┐
│  Stage 3: HTML Reports                   │
│                                          │
│  Per-sample xlsx ──► Sample pages        │
│                  ──► Variant detail pages│
│                  ──► Summary.html        │
└──────────────────────────────────────────┘
```

## Output Structure

```
output/
├── iSeq-001-S02_S82.xlsx       # Per-sample annotation (Filter, Annotation, Check sheets)
├── iSeq-001-S12_S45.xlsx
├── iSeq-001-S26_S59.xlsx
├── iSeq-001-S32_S2.xlsx
├── iSeq-001-S51_S62.xlsx
├── Combine.xlsx                 # All samples combined
├── SnapShots/
│   ├── iSeq-001-S02_S82-9-5070033.png   # sample-chr-pos.png
│   └── ...                              # one PNG per filtered variant per sample
└── html_reports/
    ├── Summary.html             # Landing page linking to all samples
    └── samples/
        ├── iSeq-001-S02_S82.html        # Variant table for this sample
        └── variants/
            └── iSeq-001-S02_S82_var0.html  # Per-variant detail page with IGV screenshot
```

## Tools and Versions

| Tool | Version | Role |
|------|---------|------|
| annovar-fast | — | Fast tabix-based functional annotation (replaces ANNOVAR) |
| cancervar-fast | — | Cancer variant classification Tier I–IV (replaces CancerVar) |
| VEP | 105 | Ensembl Variant Effect Predictor |
| snpEff | 5.0e | Variant annotation and splice effect prediction |
| TransVar | 2.5.10 | HGVS nomenclature annotation |
| bcftools | 1.13 | VCF merge/filter |
| IGV | 2.3.81 | Screenshot generation (requires Java 8) |
| Python | 3.10 | Report generation (openpyxl, pysam, cyvcf2, transvar) |

## Environment Variables

Override default tool paths at runtime:

```bash
docker run --rm \
    -e HOST_UID=$(id -u) \
    -e HOST_GID=$(id -g) \
    -e ANNOVAR_FAST=/custom/path/annovar-fast.py \
    -e CANCERVAR_FAST=/custom/path/cancervar-fast.py \
    -e VEP_CACHE=/home/user/Databases/vep \
    -e HG38_FASTA=/home/user/Databases/GRCh38/hg38.fa \
    -e IGV_JAR=/home/user/Software/IGV/IGV_2.3.81/igv.jar \
    ...
```

| Variable | Default | Description |
|----------|---------|-------------|
| `HOST_UID` | — | Host user UID for correct file ownership (standard Docker only) |
| `HOST_GID` | — | Host user GID for correct file ownership (standard Docker only) |
| `ANNOVAR_FAST` | `/data/alvin/annovar/annovar-fast/annovar-fast.py` | Path to annovar-fast.py |
| `CANCERVAR_FAST` | `/data/alvin/annovar/annovar-fast/cancervar-fast.py` | Path to cancervar-fast.py |
| `VEP_CACHE` | `$HOME/Databases/vep` | VEP cache directory |
| `HG38_FASTA` | `$HOME/Databases/GRCh38/hg38.fa` | Reference FASTA |
| `IGV_JAR` | `$HOME/Software/IGV/IGV_2.3.81/igv.jar` | IGV jar path |
| `JAVA8_PATH` | `/usr/lib/jvm/java-8-openjdk-amd64/bin/java` | Java 8 for IGV |

## Scripts

| Script | Description |
|--------|-------------|
| `processVCF-hg38.sh` | Main pipeline orchestrator — runs all 3 stages with status tracking |
| `mergeVCFannotation-optimized-hg38.sh` | Parallel annotation engine (annovar-fast, VEP, snpEff, TransVar, cancervar-fast); columns resolved by header name via `cols_by_name()` |
| `make_IGV_snapshots.py` | Headless IGV automation via xvfb |
| `excel_to_html_report.py` | Converts per-sample xlsx to interactive HTML variant reports; column positions resolved by header name, not hardcoded index |
| `entrypoint.sh` | Docker entrypoint — detects rootless vs standard Docker and sets file ownership accordingly |
| `check_docker_deps.sh` | Verifies all tools and databases are available inside the container |

## Changelog

See [CHANGES.md](CHANGES.md) for the full version history.

| Version | Date | Highlights |
|---------|------|-----------|
| main | 2026-02 | SG10K/genomeAsia tabix lookup fix; correct DB paths and column names (`AF_SEA/AF_NEA/AF_SAS`) |
| — | 2026-02 | `cols_by_name()` header-lookup in annotation combiner; skip `Combine.Filter.txt` in IGV stage |
| — | 2026-02 | `--dry-run` flag; VEP/snpEff warning surfacing; gnomAD column verification |
| — | 2026-02 | HTML improvements: CancerVar tier badge, VAF bar, 0-variant badge, COSMIC/ClinVar links |
| — | 2026-02 | Rootless Docker ownership fix; annotation stage tracking fix; Summary.html landing page |
| — | 2025 | Initial pipeline: annovar-fast + cancervar-fast integration, parallel annotation, IGV, HTML |

## License

Internal use — Clinical Genomics Pipeline.
