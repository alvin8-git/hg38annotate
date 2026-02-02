# CLAUDE.md - HG38 Annotation Pipeline

## Overview

This is a VCF annotation pipeline for iSeq panels using the HG38 reference genome. It provides:
- Parallel annotation using ANNOVAR, VEP, snpEff, and TransVar
- CancerVar classification
- SG10K and GenomeAsia population database lookups
- IGV screenshot generation
- Interactive HTML reports with embedded IGV screenshots

## Quick Start

```bash
# Run from the vcf directory containing VCF files
cd /path/to/analysis/vcf
~/Shared/SCRIPTS/claude/hg38annotate/processVCF-hg38.sh
```

## Expected Directory Structure

```
/path/to/analysis/
├── vcf/                  <- Run script from here
│   ├── *.vcf            <- VCF files to annotate
│   └── annotation/      <- Created by script
├── bam/                  <- BAM files for IGV snapshots
└── output/               <- Final output directory
    ├── *.xlsx           <- Excel files per sample
    ├── Combine.xlsx     <- Combined annotation file
    ├── annotation/      <- Annotation text files
    ├── SnapShots/       <- IGV screenshots
    ├── IgvBed/          <- BED files for IGV
    └── html_reports/    <- HTML reports
```

## Pipeline Stages

### Stage 1: Annotation
- Merges all VCF files
- Runs ANNOVAR, VEP, snpEff, TransVar in parallel
- Runs CancerVar classification
- Runs SG10K and GenomeAsia database lookups
- Generates per-sample and combined Excel files

### Stage 2: IGV Snapshots
- Generates BED files from filtered variants
- Creates IGV screenshots using xvfb-run
- Requires Java 8 and IGV 2.3.81

### Stage 3: HTML Reports
- Converts Excel files to interactive HTML reports
- Embeds IGV screenshots in variant pages
- Creates Summary.html landing page

## Command Options

```bash
# Run full pipeline (skip completed stages)
processVCF-hg38.sh

# Check pipeline status
processVCF-hg38.sh --status

# Run specific stage only
processVCF-hg38.sh --annotate
processVCF-hg38.sh --igv
processVCF-hg38.sh --html

# Run from specific stage onwards
processVCF-hg38.sh --from-igv     # IGV + HTML
processVCF-hg38.sh --from-html    # HTML only

# Force re-run even if stage is complete
processVCF-hg38.sh --force
processVCF-hg38.sh --html --force

# Control IGV parallelism
processVCF-hg38.sh --parallel 2   # Run 2 IGV instances
processVCF-hg38.sh --serial       # Run IGV sequentially

# Check dependencies
processVCF-hg38.sh --check
```

## Dependencies

### System Tools
- bcftools
- GNU parallel
- perl (with Excel::Writer::XLSX)
- java (Java 8 for IGV)
- python3 (with openpyxl)
- vcf-merge, vcf-sort, bgzip, tabix
- xvfb-run (for headless IGV)

### Annotation Tools
- ANNOVAR: `$HOME/Software/annovar/`
- snpEff: `$HOME/Software/snpEff/`
- VEP: `vep` command with cache at `$HOME/Databases/vep/`
- TransVar: `transvar` command
- CancerVar: `$HOME/Software/CancerVar/`

### Databases (HG38)
- ANNOVAR databases: `$HOME/Databases/humandb/`
- HG38 reference: `$HOME/Databases/hg38/hg38.fa`
- VEP cache: `$HOME/Databases/vep/` (GRCh38)
- SG10K: `$HOME/Databases/SG10K.hg38.vcf/`
- GenomeAsia: `$HOME/Databases/genomeAsia/`

### IGV
- IGV JAR: `$HOME/Software/IGV-snapshot-automator/bin/IGV_2.3.81/igv.jar`
- Java 8: `/usr/lib/jvm/java-8-openjdk-amd64/bin/java`

## Environment Variables

You can override default paths using environment variables:

```bash
export ANNOVAR_DIR=/path/to/annovar
export SNPEFF_DIR=/path/to/snpEff
export CANCERVAR_DIR=/path/to/CancerVar
export HUMANDB=/path/to/humandb
export VEP_CACHE=/path/to/vep
export HG38_FASTA=/path/to/hg38.fa
export IGV_JAR=/path/to/igv.jar
export JAVA8_PATH=/path/to/java8
export IGV_PARALLEL_JOBS=2
```

## Scripts

| Script | Description |
|--------|-------------|
| `processVCF-hg38.sh` | Main orchestration script |
| `mergeVCFannotation-optimized-hg38.sh` | Annotation pipeline |
| `make_IGV_snapshots.py` | IGV screenshot generator (HG38 default) |
| `excel_to_html_report.py` | HTML report generator |

## Output Files

### Per-Sample Files
- `{sample}.xlsx` - Multi-worksheet Excel file with:
  - Filter sheet - Filtered variants
  - Annotation sheet - Full annotation
  - Check sheet - Annotation concordance
  - Compare sheets - Sample comparison data

### Combined Files
- `Combine.xlsx` - Combined annotation for all samples
- `Combine.Filter.txt` - Combined filtered variants
- `Combine.annotation.txt` - Combined full annotation

### HTML Reports
- `html_reports/Summary.html` - Landing page with all samples
- `html_reports/{sample}.html` - Per-sample variant reports with embedded IGV screenshots

## Filtering Rules

Variants are filtered based on:
- Intronic variants removed (unless splice site)
- Synonymous variants removed
- UTR variants removed
- Read depth >= 100
- VAF > 5%
