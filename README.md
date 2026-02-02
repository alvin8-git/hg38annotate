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

### Prerequisites

Before building the Docker container, you need to set up the annotation tool directories in the build context:

```bash
cd /path/to/hg38annotate

# Copy or link annotation tools (requires ~500MB)
cp -r ~/Software/annovar ./annovar
cp -r ~/Software/snpEff ./snpEff
cp -r ~/Software/CancerVar ./CancerVar
cp -r ~/Software/ensembl-vep ./ensembl-vep
```

Or if symlinks are supported on your filesystem:
```bash
ln -s ~/Software/annovar ./annovar
ln -s ~/Software/snpEff ./snpEff
ln -s ~/Software/CancerVar ./CancerVar
ln -s ~/Software/ensembl-vep ./ensembl-vep
```

### Building

```bash
docker build -t hg38annotate .
# Or with docker-compose:
docker-compose build
```

### Running

**Interactive shell:**
```bash
docker-compose run --rm hg38annotate
```

**Run pipeline:**
```bash
docker run -v ${HOME}/Databases:/home/user/Databases:ro \
           -v $(pwd)/data:/data \
           hg38annotate processVCF-hg38.sh
```

### Required Database Mounts (HG38/GRCh38)

| Mount Point | Description |
|-------------|-------------|
| `/home/user/Databases/humandb` | ANNOVAR hg38 databases |
| `/home/user/Databases/GRCh38` | GRCh38 reference genome (hg38.fa) |
| `/home/user/Databases/vep` | VEP GRCh38 cache (~28GB) |
| `/home/user/Databases/snpEff` | snpEff GRCh38.p13.RefSeq database |
| `/home/user/Databases/SG10K.hg38.vcf` | SG10K HG38 population database |
| `/home/user/Databases/iSeq` | iSeq reference VCFs (HG38) |

### Service Configurations

The `docker-compose.yml` provides three service configurations:

1. **hg38annotate** - Full setup with all databases mounted
2. **hg38annotate-minimal** - Minimal with specific database paths
3. **hg38annotate-dev** - Development mode with writable script mounts

### Verify Installation

```bash
docker run --rm hg38annotate /home/user/Scripts/check_docker_deps.sh
```

## License

Clinical Genomics Pipeline - Internal Use
