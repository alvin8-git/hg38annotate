# hg38annotate

A Docker-based VCF annotation pipeline for the HG38/GRCh38 reference genome. Designed for iSeq amplicon panels — takes raw VCF files through three stages (Annotate → IGV Snapshots → HTML Reports) and produces per-sample Excel files, IGV screenshots, and interactive HTML variant reports.

## Features

- **Parallel multi-tool annotation** — annovar-fast, VEP, snpEff, and TransVar run concurrently
- **Cancer classification** — CancerVar Tier I–IV scoring via cancervar-fast
- **Population databases** — SG10K (AF_CHS/AF_INS/AF_MAS) and GenomeAsia (AF_SEA/AF_NEA/AF_SAS) via tabix lookup; gnomAD, ExAC, ESP6500, 1000 Genomes via annovar-fast
- **IGV screenshots** — Automated headless IGV 2.3.81 snapshots for each filtered variant (reads sorted by base at variant position)
- **Interactive HTML reports** — Per-sample variant pages with embedded IGV screenshots, CancerVar tier badges, VAF bar, ClinVar/COSMIC links, ACMG chips, and population frequency tables
- **Stage control** — Run all three stages or individual stages; skip already-complete stages; `--force` to re-run; `--dry-run` to preview

---

## Contents

1. [Prerequisites](#prerequisites)
2. [Installation](#installation)
3. [Quick Start](#quick-start)
4. [Usage](#usage)
5. [Testing](#testing)
6. [Configuration](#configuration)
7. [Pipeline Architecture](#pipeline-architecture)
8. [Output Structure](#output-structure)
9. [Tools & Versions](#tools--versions)
10. [Changelog](#changelog)

---

## Prerequisites

### Required software

| Requirement | Notes |
|-------------|-------|
| Docker ≥ 20.10 | Rootless or standard mode both supported |
| `Software.tar.gz` | Annotation tool bundle — download from [GitHub Releases](https://github.com/alvin8-git/hg38annotate/releases) |
| annovar-fast | From [github.com/alvin8-git/annovar-fast](https://github.com/alvin8-git/annovar-fast) |

### Required databases (mounted at runtime)

| Database | Size | Path inside container |
|----------|------|-----------------------|
| GRCh38 reference FASTA | ~3 GB | `$DB_BASE/GRCh38/hg38.fa` |
| VEP GRCh38 RefSeq cache | ~28 GB | `$DB_BASE/vep/` |
| snpEff GRCh38.p13.RefSeq | ~1 GB | `$DB_BASE/snpEff/` |
| SG10K (tabix-indexed) | ~2 MB | `$DB_BASE/SG10k/SG10K.genes.txt.gz` |
| GenomeAsia (tabix-indexed) | ~600 MB | `$DB_BASE/genomeAsia/genomeAsia.All.hg38.txt.gz` |
| humandb-tbi (annovar-fast) | ~30 GB | Mounted separately — see [Configuration](#databases) |

`$DB_BASE` defaults to `$HOME/Databases/hg38annotate` and is overridable at runtime (see [Configuration](#configuration)).

---

## Installation

### 1. Clone the repository

```bash
git clone https://github.com/alvin8-git/hg38annotate.git
cd hg38annotate
```

### 2. Download and extract annotation tools

ANNOVAR, snpEff, and VEP are too large for git and are distributed as a release archive.

```bash
# Download from the GitHub releases page
wget https://github.com/alvin8-git/hg38annotate/releases/latest/download/Software.tar.gz
tar -xzf Software.tar.gz
```

This extracts the following directories into the repo root, which are required for `docker build`:

```
annovar/        ANNOVAR Perl scripts
snpEff/         snpEff jar + scripts
ensembl-vep/    VEP software (databases mounted at runtime)
```

### 3. Build the Docker image

```bash
docker build -t hg38annotate:latest .
```

- Build time: ~10–20 minutes (VEP module installation dominates)
- Image size: ~2.5 GB (databases are mounted at runtime, not baked in)

> **Note for CentOS 7 hosts:** The build uses `dpkg-divert` stubs to work around `pthread_create EPERM` from the seccomp profile on kernel 3.10.x. No special flags are needed; the Dockerfile handles this automatically.

### 4. Set up databases

Organise all annotation databases under a single root directory (default: `~/Databases/hg38annotate`):

```
~/Databases/hg38annotate/
├── GRCh38/
│   ├── hg38.fa          # GRCh38 reference FASTA (bgzip optional)
│   └── hg38.fa.fai      # samtools fai index
├── vep/                  # VEP GRCh38 RefSeq cache
│   └── homo_sapiens_refseq/
├── snpEff/               # snpEff database
│   └── GRCh38.p13.RefSeq/
├── SG10k/                # SG10K Singapore population (tabix-indexed)
│   ├── SG10K.genes.txt.gz
│   └── SG10K.genes.txt.gz.tbi
└── genomeAsia/           # GenomeAsia 100K (tabix-indexed)
    ├── genomeAsia.All.hg38.txt.gz
    └── genomeAsia.All.hg38.txt.gz.tbi
```

`humandb-tbi` (annovar-fast databases) is kept at its own location and mounted separately — see [Databases](#databases) below.

---

## Quick Start

```bash
# Run the full pipeline on your VCF directory
docker run --rm \
    -e HOST_UID=$(id -u) \
    -e HOST_GID=$(id -g) \
    -e HUMANDB=/path/to/humandb-tbi \
    -v ~/Databases/hg38annotate:/home/user/Databases/hg38annotate:ro \
    -v /path/to/annovar-fast:/path/to/annovar-fast:ro \
    -v /path/to/humandb-tbi:/path/to/humandb-tbi:ro \
    -v /path/to/your/analysis:/data \
    hg38annotate:latest bash -c "cd /data/vcf && processVCF-hg38.sh"
```

Expects `/path/to/your/analysis/vcf/*.vcf` as input. Output appears in `/path/to/your/analysis/output/`.

> **File ownership:** Pass `-e HOST_UID=$(id -u) -e HOST_GID=$(id -g)` for standard Docker so output files are owned by your host user. Not required for rootless Docker.

---

## Usage

All commands run from within the container with `cd /data/vcf` first.

```bash
# Full pipeline (all 3 stages; skips stages already complete)
processVCF-hg38.sh

# Run a specific stage only
processVCF-hg38.sh --annotate       # Stage 1: annotation + Excel
processVCF-hg38.sh --igv            # Stage 2: IGV screenshots
processVCF-hg38.sh --html           # Stage 3: HTML reports

# Run from a specific stage onwards
processVCF-hg38.sh --from-igv       # Stage 2 + 3
processVCF-hg38.sh --from-html      # Stage 3 only

# Re-run even if the stage already has output
processVCF-hg38.sh --force
processVCF-hg38.sh --annotate --force

# Utilities
processVCF-hg38.sh --status         # Show which stages are complete
processVCF-hg38.sh --check          # Verify all tools and databases are present
processVCF-hg38.sh --dry-run        # Preview what would run without executing

# IGV parallelism (defaults to auto: RAM ÷ 5, capped 1–4)
processVCF-hg38.sh --parallel 2     # Run 2 IGV instances in parallel
processVCF-hg38.sh --serial         # Run IGV sequentially (--parallel 1)

processVCF-hg38.sh --help
```

Flag aliases: `--snapshots` = `--igv`, `--reports` = `--html`, `-f` = `--force`, `-n` = `--dry-run`, `-j N` = `--parallel N`.

---

## Testing

TestData with 5 iSeq panel samples (VCF + BAM files) is included in `TestData/`.

### Run the test pipeline

```bash
docker run --rm \
    -e HOST_UID=$(id -u) \
    -e HOST_GID=$(id -g) \
    -e HUMANDB=/path/to/humandb-tbi \
    -v ~/Databases/hg38annotate:/home/user/Databases/hg38annotate:ro \
    -v /path/to/annovar-fast:/path/to/annovar-fast:ro \
    -v /path/to/humandb-tbi:/path/to/humandb-tbi:ro \
    -v $(pwd)/TestData:/data \
    hg38annotate:latest bash -c "cd /data/vcf && processVCF-hg38.sh"
```

### Expected results

| Stage | Time | Output |
|-------|------|--------|
| **Annotation** | ~35 s | `TestData/output/*.xlsx` — 5 per-sample + `Combine.xlsx`; 27 variants across 5 samples; SG10K and GenomeAsia frequencies populated for matching SNPs |
| **IGV snapshots** | ~80 s | 10 PNG files in `TestData/output/SnapShots/` — one per filtered variant per sample; reads sorted by base at variant position |
| **HTML reports** | ~2 s | `TestData/output/html_reports/Summary.html` + 5 sample pages; embedded IGV screenshots, CancerVar tiers, population frequencies |

### Verify tool installation only

```bash
docker run --rm hg38annotate:latest /home/user/Scripts/check_docker_deps.sh
```

Checks: core tools (bcftools, tabix, vcf-merge/sort, parallel), annotation tools (VEP, snpEff, TransVar, annovar-fast), Perl/Python modules, IGV, pipeline scripts, and database directories.

---

## Configuration

### Environment variables

Set these with `-e VAR=value` in `docker run`.

#### Database paths

| Variable | Default | Description |
|----------|---------|-------------|
| `DB_BASE` | `$HOME/Databases/hg38annotate` | **Master database root** — override to relocate all databases at once |
| `HUMANDB` | `$DB_BASE/humandb-tbi` | annovar-fast tabix-indexed databases (often mounted separately) |
| `VEP_CACHE` | `$DB_BASE/vep` | VEP GRCh38 RefSeq cache directory |
| `HG38_FASTA` | `$DB_BASE/GRCh38/hg38.fa` | GRCh38 reference FASTA |
| `SG10K_DB` | `$DB_BASE/SG10k/SG10K.genes.txt.gz` | SG10K bgzipped + tabix-indexed file |
| `GENOMEASIA_DB` | `$DB_BASE/genomeAsia/genomeAsia.All.hg38.txt.gz` | GenomeAsia bgzipped + tabix-indexed file |

#### Tool paths

| Variable | Default (inside container) | Description |
|----------|---------------------------|-------------|
| `ANNOVAR_FAST` | `/data/alvin/annovar/annovar-fast/annovar-fast.py` | Path to annovar-fast.py |
| `CANCERVAR_FAST` | `/data/alvin/annovar/annovar-fast/cancervar-fast.py` | Path to cancervar-fast.py |
| `IGV_JAR` | `$HOME/Software/IGV/IGV_2.3.81/igv.jar` | IGV jar (bundled in image) |
| `JAVA8_PATH` | `/usr/lib/jvm/java-8-openjdk-amd64/bin/java` | Java 8 for IGV |
| `IGV_PARALLEL_JOBS` | `0` (auto: RAM ÷ 5, cap 1–4) | Number of parallel IGV instances |

#### File ownership (standard Docker only)

| Variable | Default | Description |
|----------|---------|-------------|
| `HOST_UID` | `1000` | Host user UID — set to `$(id -u)` |
| `HOST_GID` | `HOST_UID` | Host user GID — set to `$(id -g)` |

### Databases

All databases under `$DB_BASE` can be mounted as a single volume:

```bash
-v /your/Databases/hg38annotate:/home/user/Databases/hg38annotate:ro
```

**`humandb-tbi`** (annovar-fast databases, ~30 GB) is typically kept separately and mounted at the same absolute path as on the host:

```bash
# humandb-tbi is at /data/annovar/humandb-tbi on the host
-e HUMANDB=/data/annovar/humandb-tbi \
-v /data/annovar/humandb-tbi:/data/annovar/humandb-tbi:ro
```

### Variant filtering rules

Variants are excluded from the Filter sheet if they match any of:

- Intronic (unless `splice_donor_variant` or `splice_acceptor_variant`)
- Synonymous SNV
- 3′ UTR / 5′ UTR
- Read depth < 100
- VAF ≤ 5%

---

## Pipeline Architecture

```
Input: *.vcf files in vcf/
         │
         ▼
┌──────────────────────────────────────────────┐
│  Stage 1: Annotation (~35 s / 27 variants)   │
│                                              │
│  Filter + merge VCFs (bcftools + vcf-merge)  │
│         │                                    │
│  ┌──────┴──────────────────────────────┐     │
│  │  Parallel annotation                │     │
│  │  annovar-fast  VEP  snpEff TransVar │     │
│  └──────┬──────────────────────────────┘     │
│         │                                    │
│  cancervar-fast → CancerVar tiers            │
│  tabix SG10K + GenomeAsia → population AF    │
│         │                                    │
│  Merge annotations → per-sample xlsx         │
│  + Combine.xlsx                              │
└──────────────────────────────────────────────┘
         │
         ▼
┌──────────────────────────────────┐
│  Stage 2: IGV Snapshots (~80 s)  │
│                                  │
│  Filtered variants → BED files   │
│  BAM + BED → xvfb-run + IGV     │
│  sort base chr:pos → PNG         │
└──────────────────────────────────┘
         │
         ▼
┌──────────────────────────────────────────────┐
│  Stage 3: HTML Reports (~2 s)                │
│                                              │
│  Per-sample xlsx → sample pages              │
│  + per-variant detail pages                  │
│  + Summary.html landing page                 │
└──────────────────────────────────────────────┘
```

---

## Output Structure

```
output/
├── iSeq-001-S02_S82.xlsx       # Per-sample: Filter / Annotation / Check / Compare sheets
├── iSeq-001-S12_S45.xlsx
├── ...
├── Combine.xlsx                # All samples combined (same sheet structure)
├── annotation/                 # Intermediate annotation text files
│   ├── Combine.annotation.txt
│   ├── Combine.Filter.txt
│   └── {sample}.annotation.txt ...
├── SnapShots/
│   ├── {sample}-{chr}-{pos}.png   # One PNG per filtered variant per sample
│   └── ...
└── html_reports/
    ├── Summary.html            # Landing page — links to all samples
    └── samples/
        ├── {sample}.html       # Variant table for this sample
        └── variants/
            └── {sample}_var{N}.html   # Per-variant detail: IGV screenshot,
                                        # CancerVar tier, VAF bar, population AF,
                                        # ClinVar/COSMIC links, prediction scores
```

---

## Tools & Versions

| Tool | Version | Role |
|------|---------|------|
| annovar-fast | — | Tabix-based functional annotation (replaces ANNOVAR) |
| cancervar-fast | — | Cancer Tier I–IV classification (replaces CancerVar) |
| VEP | 105 (software) + 115 cache | Ensembl Variant Effect Predictor |
| snpEff | 5.0e | Splice effect prediction + functional annotation |
| TransVar | 2.5.10 | HGVS nomenclature |
| bcftools | 1.13 | VCF merge, filter, stats |
| IGV | 2.3.81 | Screenshot generation (requires Java 8) |
| Python | 3.10 | Report generation (openpyxl, cyvcf2, pysam, transvar) |

---

## Changelog

See [CHANGES.md](CHANGES.md) for the full history.

| Date | Highlights |
|------|-----------|
| 2026-02 | VEP 115 cache (`--cache_version 115`): ClinVar 202502, GENCODE 49, gnomAD v4.1 in cache (no column header change) |
| 2026-02 | Unified `DB_BASE` database root; all paths configurable via a single env var |
| 2026-02 | IGV `sort base chr:pos` fix — reads grouped by alt vs ref at the variant site |
| 2026-02 | IGV 5-minute per-sample timeout; GenomeAsia AF columns in HTML; source-prefixed population labels |
| 2026-02 | SG10K/GenomeAsia rewritten to use `tabix` per-variant lookup; correct file paths and column names |
| 2026-02 | `cols_by_name()` header-based column resolution in annotation combiner and HTML generator |
| 2026-02 | Rootless Docker detection in entrypoint; annotation stage completion tracking |
| 2026-02 | Docker build fixes for CentOS 7 / kernel 3.10.x (JVM seccomp, pip threading, Perl modules) |
| 2025 | Initial pipeline: annovar-fast + cancervar-fast integration, parallel annotation, IGV, HTML |

---

## License

Internal use — Clinical Genomics Pipeline.
