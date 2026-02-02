# hg38annotate

VCF annotation and HTML report generation pipeline for HG38 reference genome. Adapted from the processiSeq-hg38.sh pipeline for standalone use with VCF/BAM files.

## Overview

This pipeline takes VCF files and generates:
1. Multi-tool annotations (ANNOVAR, VEP, snpEff, TransVar, CancerVar)
2. Combined Excel output (Combine.xlsx)
3. IGV screenshots for each variant
4. Interactive HTML variant reports with embedded IGV screenshots

## Files

| File | Description |
|------|-------------|
| `processVCF-hg38.sh` | Main orchestration script with 3 stages: Annotation, IGV, HTML |
| `mergeVCFannotation-optimized-hg38.sh` | Parallel annotation pipeline using ANNOVAR, VEP, snpEff, TransVar |
| `make_IGV_snapshots.py` | IGV batch screenshot automation (requires xvfb, Java 8) |
| `excel_to_html_report.py` | Converts Combine.xlsx to interactive HTML reports |

## Usage

### Full Pipeline
```bash
cd /path/to/analysis
~/Shared/SCRIPTS/claude/hg38annotate/processVCF-hg38.sh
```

The script looks for:
- `bam/` directory containing BAM files
- `vcf/` directory containing VCF files

### Individual Components

**Annotation only:**
```bash
./mergeVCFannotation-optimized-hg38.sh sample.vcf
```

**IGV snapshots only:**
```bash
python3 make_IGV_snapshots.py sample.bam -r regions.bed -o SnapShots -bin /path/to/igv.jar -suffix sample_name
```

**HTML report only:**
```bash
python3 excel_to_html_report.py Combine.xlsx html_report SnapShots
```

## HTML Report Features

The HTML report matches the processVCF style with:

- **Landing page**: Clickable sample cards showing variant/gene counts
- **Sample pages**: Variant tables with Gene, Location, HGVSc/p, VAF, DP
- **Variant detail pages**: Collapsible panels with color-coded sections:
  - **Blue**: Basic Variant Information (Chr, Pos, Ref, Alt, Gene, HGVSc/p, VAF, etc.)
  - **Purple**: IGV Screenshot (embedded PNG)
  - **Green**: Sample Comparison Data
  - **Gray**: Additional Variant Information
  - **Indigo**: Population Frequency Databases (with visual frequency bars)
  - **Purple**: ACMG Classification Criteria (chip/button format for PVS1, PS1-4, PM1-6, PP1-5, BA1, BS1-4, BP1-7)
  - **Orange**: Computational Predictions (score table with D/T/P/B badges)

Empty fields are automatically hidden.

## Column Structure (Combine.xlsx)

| Columns | Content |
|---------|---------|
| 1 | SAMPLE |
| 2-19 | Basic variant info (Chr, Pos, Ref, Alt, GT, GENE, Transcript, HGVSg, HGVSc, HGVSp, AD, DP, QUAL, VAF, snp141, annotation, cosmic91, CancerVar) |
| 20-21 | Sample comparison (iSeq203, TMSP904) |
| 22-30 | Additional info (FILTER, ExonicFunc, Func, cytoBand, Consequence, STRAND, VARIANT_CLASS, EXON, INTRON) |
| 31-88 | Population frequencies (SG10K, ESP, ExAC, 1000g, Kaviar, gnomAD, HRC, GME, etc.) |
| 89-122 | ACMG criteria (InterVar, PVS1, PS1-4, PM1-6, PP1-5, BA1, BS1-4, BP1-7, ClinVar fields) |
| 123-152 | Computational predictions (MCAP, REVEL, SIFT, PolyPhen2, LRT, MutationTaster, FATHMM, CADD, GERP++, phyloP, SiPhy, etc.) |

## Dependencies

### Annotation Tools
- ANNOVAR (`~/Software/annovar/`)
- Ensembl VEP (via conda or docker)
- snpEff (`~/Software/snpEff/`)
- TransVar (via pip)
- CancerVar

### Databases
- ANNOVAR humandb (`~/Databases/humandb/`)
- HG38 reference (`~/Databases/WholeGenomeFASTA/GRCh38/`)

### Python Packages
```bash
pip install openpyxl
```

### IGV Requirements
- Java 8 (`/usr/lib/jvm/java-8-openjdk-amd64/bin/java`)
- IGV jar file
- xvfb-run (for headless operation)

## Output Structure

```
output-hg38/
├── bam/                    # Input BAM files
├── vcf/                    # Input VCF files
├── Combine.xlsx            # Combined annotation results
├── SnapShots/              # IGV screenshots (sample-chr-pos.png)
└── html_report/
    ├── index.html          # Landing page with sample cards
    └── samples/
        ├── sample1.html    # Sample variant table
        └── variants/
            └── sample1_var0.html  # Variant detail pages
```

## Docker Container

The Docker container packages all annotation tools (ANNOVAR, VEP, snpEff, TransVar, CancerVar, IGV) in a single image. Databases are mounted at runtime to keep the image size manageable.

### Quick Start

```bash
# 1. Clone the repository
git clone https://github.com/alvin8-git/hg38annotate.git
cd hg38annotate

# 2. Copy annotation tools to build context (see Prerequisites below)
cp -r ~/Software/annovar ./annovar
cp -r ~/Software/snpEff ./snpEff
cp -r ~/Software/CancerVar ./CancerVar
cp -r ~/Software/ensembl-vep ./ensembl-vep

# 3. Build the image
docker build -t hg38annotate:latest .

# 4. Run with databases mounted
docker run -v ${HOME}/Databases:/home/user/Databases:ro \
           -v $(pwd)/data:/data \
           hg38annotate:latest processVCF-hg38.sh
```

### Prerequisites

Before building, copy the annotation tool directories into the build context:

```bash
cd /path/to/hg38annotate

# Copy annotation tools (~500MB total)
cp -r ~/Software/annovar ./annovar
cp -r ~/Software/snpEff ./snpEff
cp -r ~/Software/CancerVar ./CancerVar
cp -r ~/Software/ensembl-vep ./ensembl-vep
```

**Note:** These directories are excluded from git via `.gitignore` since they contain large binaries.

### Building the Image

```bash
# Standard build
docker build -t hg38annotate:latest .

# Or with docker-compose
docker-compose build
```

### Running the Container

**Interactive shell:**
```bash
docker run -it --rm \
    -v ${HOME}/Databases:/home/user/Databases:ro \
    -v $(pwd)/data:/data \
    hg38annotate:latest bash
```

**Run full pipeline:**
```bash
docker run --rm \
    -v ${HOME}/Databases:/home/user/Databases:ro \
    -v $(pwd)/data:/data \
    hg38annotate:latest processVCF-hg38.sh
```

**Run annotation only:**
```bash
docker run --rm \
    -v ${HOME}/Databases:/home/user/Databases:ro \
    -v $(pwd)/data:/data \
    hg38annotate:latest mergeVCFannotation-optimized-hg38.sh /data/sample.vcf
```

**Using docker-compose:**
```bash
# Interactive shell
docker-compose run --rm hg38annotate

# Development mode (scripts mounted as writable)
docker-compose run --rm hg38annotate-dev
```

### Required Database Mounts (HG38/GRCh38)

| Mount Point | Description | Size |
|-------------|-------------|------|
| `/home/user/Databases/humandb` | ANNOVAR hg38 databases | ~50GB |
| `/home/user/Databases/GRCh38` | GRCh38 reference genome (hg38.fa + index) | ~3GB |
| `/home/user/Databases/vep` | VEP GRCh38 cache | ~28GB |
| `/home/user/Databases/snpEff` | snpEff GRCh38.p13.RefSeq database | ~1GB |
| `/home/user/Databases/SG10K.hg38.vcf` | SG10K HG38 population database | ~2GB |
| `/home/user/Databases/iSeq` | iSeq reference VCFs (HG38) | ~100MB |

### Included Tools and Versions

| Tool | Version | Purpose |
|------|---------|---------|
| ANNOVAR | Latest | Functional annotation |
| VEP | 105.0 | Ensembl variant effect prediction |
| snpEff | 5.0e | Variant annotation and effect prediction |
| TransVar | Latest | HGVS notation annotation (hg38 configured) |
| CancerVar | Latest | Cancer variant interpretation |
| IGV | 2.3.81 | Screenshot generation (Java 8) |

### Service Configurations

The `docker-compose.yml` provides three service configurations:

1. **hg38annotate** - Full setup with all databases from `${HOME}/Databases`
2. **hg38annotate-minimal** - Minimal with specific database path mounts
3. **hg38annotate-dev** - Development mode with writable script mounts for testing

### Verify Installation

Run the dependency check script to verify all tools are properly installed:

```bash
docker run --rm hg38annotate:latest /home/user/Scripts/check_docker_deps.sh
```

Expected output shows 49 passed checks with warnings only for unmounted databases.

### Testing Individual Tools

```bash
# Test ANNOVAR
docker run --rm hg38annotate:latest \
    perl /home/user/Software/annovar/table_annovar.pl 2>&1 | head -5

# Test VEP
docker run --rm hg38annotate:latest vep --help | head -10

# Test snpEff
docker run --rm hg38annotate:latest \
    java -jar /home/user/Software/snpEff/snpEff.jar -version

# Test TransVar (hg38)
docker run --rm hg38annotate:latest transvar config --refversion hg38
```

## License

Clinical Genomics Pipeline - Internal Use
