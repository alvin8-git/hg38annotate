#!/bin/bash
# =============================================================================
# mergeVCFannotation-optimized-hg38.sh - Optimized VCF Annotation Pipeline (HG38)
# =============================================================================
# This script is an optimized version for HG38 that:
# - Runs independent annotations in parallel (ANNOVAR, VEP, snpEff, TransVar)
# - Runs database comparisons in parallel
# - Runs database lookups in parallel (SG10K, genomeAsia)
# - Provides better progress tracking and error handling
# - Supports iSeq panels
#
# Usage: Run from directory containing VCF files
#   ./mergeVCFannotation-optimized-hg38.sh [iseq]
#
# Modes:
#   iseq  - iSeq panel (default): Clinical and iSeq comparisons
#
# =============================================================================

set -e  # Exit on error

# =============================================================================
# MODE SELECTION
# =============================================================================

MODE="${1:-iseq}"
MODE=$(echo "$MODE" | tr '[:upper:]' '[:lower:]')

# =============================================================================
# CONFIGURATION
# =============================================================================

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Paths
HOME_DIR="${HOME:-/home/alvin}"
SCRIPTS_DIR="$SCRIPT_DIR"
SOFTWARE_DIR="$HOME_DIR/Software"
DATABASES_DIR="$HOME_DIR/Databases"

# Annotation tools
ANNOVAR_FAST="${ANNOVAR_FAST:-/data/alvin/annovar/annovar-fast/annovar-fast.py}"
CANCERVAR_FAST="${CANCERVAR_FAST:-/data/alvin/annovar/annovar-fast/cancervar-fast.py}"
SNPEFF_DIR="${SNPEFF_DIR:-$SOFTWARE_DIR/snpEff}"

# Databases
HUMANDB="${HUMANDB:-$DATABASES_DIR/humandb}"
VEP_CACHE="${VEP_CACHE:-$DATABASES_DIR/vep}"
HG38_FASTA="${HG38_FASTA:-$DATABASES_DIR/hg38/hg38.fa}"
REFSEQ_TRANSCRIPTS="${REFSEQ_TRANSCRIPTS:-$DATABASES_DIR/Ensembldata/RefSeqSelectTranscript.txt}"
SG10K_DB="${SG10K_DB:-$DATABASES_DIR/SG10K.hg38.vcf/SG10K.genes.txt}"
GENOMEASIA_DB="${GENOMEASIA_DB:-$DATABASES_DIR/genomeAsia/genomeAsia.genes.txt}"

# Mode-specific configuration
VCF_DATABASE="$DATABASES_DIR/iSeq/vcf-hg38"
VCF_DATABASE_TMSP="$DATABASES_DIR/TMSPvcf/TSMPclean/Clinical-hg38"
COMPARE_DBS=("$VCF_DATABASE" "$VCF_DATABASE_TMSP")
COMPARE_NAMES=("iSeq" "TMSP")
DO_IKZF1_FIX=true

# Processing settings
MAX_PARALLEL_JOBS=4
MEM_SUSPEND="3G"

# =============================================================================
# INTEGRATED FUNCTIONS
# =============================================================================

# VCFstats function - Extracts useful statistics from a VCF file
vcf_stats() {
    local vcf="$1"
    local sampleName=$(basename "$vcf" .vcf)

    [ -f "$sampleName.VCFstats.txt" ] && return 0

    paste \
        <(cat \
            <(echo -e "chr\tpos\tRef\tAlt\tGT\tAD\tDP\tQUAL\tVAF") \
            <(bcftools query -f '%CHROM %POS %REF %ALT [%GT %AD %DP %QUAL ]\n' "$vcf" | \
            sed -r 's/ +/\t/g' | cut -f1-8 | sed 's/,/\t/g' | \
            awk '{if($8>0)print $0"\t"$7/$8 ;else print $0"\t-"}' | cut -f1-5,7- )) \
        <(cat \
            <(echo -e "RD,AD") \
            <(bcftools query -f '[%AD]\n' "$vcf")) \
        > "$sampleName.VCFstats.txt"
}

export -f vcf_stats

# filterAnno function - Filters annotation file for iSeq
filter_anno_iseq() {
    local FILE="$1"
    local SAMPLE=$(basename "$FILE" .annotation.txt)

    [ -f "$SAMPLE.Filter.txt" ] && return 0

    # Filter rules for iSeq:
    # - Remove intronic variants (unless splice site)
    # - Remove synonymous variants
    # - Remove UTR variants
    # - Keep variants with VAF > 5%
    # - Keep variants with DP >= 100

    cat \
        <(awk -F"\t" '{if(NR==1)print}' "$FILE") \
        <(awk -F"\t" '{if(NR!=1)print}' "$FILE" | \
        awk -F"\t" '{if(!($23=="intronic"&&$25=="intron_variant"))print}' | \
        awk -F"\t" '{if(!($23=="intronic"&&$25!~/splice_donor_variant|splice_acceptor_variant/))print}' | \
        awk -F"\t" '{if(!($22=="synonymous SNV"&&$25=="synonymous_variant"))print}' | \
        awk -F"\t" '{if(!($23=="UTR3"&&$25=="3_prime_UTR_variant"))print}' | \
        awk -F"\t" '{if(!($23=="UTR5"&&$25=="5_prime_UTR_variant"))print}' | \
        awk -F"\t" '{if($12>=100)print}' | \
        awk -F"\t" '{if($14>0.05)print}' | \
        sort -k1,1V -k2,2n) \
        > "$SAMPLE.Filter.txt"
}

export -f filter_anno_iseq

# =============================================================================
# COLUMN EXTRACTION HELPERS
# =============================================================================

# cols_by_name FILE COL [COL ...]
#
# Extract named columns from a tab-separated file that has a header row.
# Columns are emitted in the ORDER LISTED (not the order they appear in the file).
# Leading/trailing whitespace is stripped from header values before matching, so
# column names with embedded spaces (e.g. CancerVar output) are handled correctly.
# Unknown column names produce empty fields.
#
# When the file is absent the column names are written as a header row with no
# data rows; paste will then emit empty strings for all data rows from that input.
#
# Usage in a paste pipeline:
#   paste <(cols_by_name file.txt "ColA" "ColB") <(cols_by_name other.txt "X")
#
cols_by_name() {
    local file="$1"
    shift

    if [ ! -f "$file" ]; then
        # Emit column names as a header row only; paste fills empty strings for data.
        ( IFS=$'\t'; echo "$*" )
        return 0
    fi

    # Use \x01 as a safe separator — column names may contain spaces, tabs would
    # be misinterpreted, and \x01 never appears in biological column names.
    local col_spec ncols
    col_spec=$(printf '%s\x01' "$@")
    ncols=$#

    awk -v col_spec="$col_spec" -v ncols="$ncols" '
    BEGIN {
        FS  = "\t"
        OFS = "\t"
        n   = split(col_spec, want, "\x01")
        if (n > 0 && want[n] == "") n--   # discard trailing empty from split
    }
    NR == 1 {
        # Build header → column-index map, stripping leading/trailing whitespace
        for (i = 1; i <= NF; i++) {
            h = $i
            gsub(/^[[:space:]]+|[[:space:]]+$/, "", h)
            hdr[h] = i
        }
        # Print header using the requested column names (exactly as passed)
        for (k = 1; k <= n; k++)
            printf "%s%s", want[k], (k < n ? OFS : "\n")
        next
    }
    {
        for (k = 1; k <= n; k++) {
            col = want[k]
            gsub(/^[[:space:]]+|[[:space:]]+$/, "", col)
            val = (col in hdr) ? $(hdr[col]) : ""
            printf "%s%s", val, (k < n ? OFS : "\n")
        }
    }' "$file"
}

# =============================================================================
# LOGGING
# =============================================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() {
    echo -e "${BLUE}[$(date '+%H:%M:%S')]${NC} INFO: $1"
}

log_success() {
    echo -e "${GREEN}[$(date '+%H:%M:%S')]${NC} DONE: $1"
}

log_warn() {
    echo -e "${YELLOW}[$(date '+%H:%M:%S')]${NC} WARN: $1"
}

log_error() {
    echo -e "${RED}[$(date '+%H:%M:%S')]${NC} ERROR: $1" >&2
}

log_step() {
    echo -e "\n${GREEN}======================== $1 ========================${NC}"
}

# =============================================================================
# ANNOTATION FUNCTIONS
# =============================================================================

run_annovar() {
    local vcf="$1"
    local sample=$(basename "$vcf" .vcf)

    [ -f "$sample.annovar.txt" ] && return 0

    log_info "Starting ANNOVAR-fast for $sample"

    python3 "$ANNOVAR_FAST" "$vcf" -o "$sample.annovar.txt"

    log_success "ANNOVAR-fast completed for $sample"

    verify_annovar_columns "$sample.annovar.txt"
}

# Verify that expected gnomAD genome column names are present in the annovar output header.
# Logs a warning if a column is missing, which can indicate that annovar-fast or humandb
# version changes have renamed the gnomAD columns (e.g. gnomad30 -> gnomad41).
verify_annovar_columns() {
    local annovar_file="$1"

    [ -f "$annovar_file" ] || return 0

    local header
    header=$(head -1 "$annovar_file")

    # Key gnomAD genome columns that combine_annotations() extracts by position.
    # If any of these are absent the combined output will have wrong values in those columns.
    local -a expected_cols=(
        "gnomad41_genome_AF"
        "gnomad41_genome_AF_afr"
        "gnomad41_genome_AF_amr"
        "gnomad41_genome_AF_eas"
        "gnomad41_genome_AF_nfe"
        "gnomad41_exome_AF"
    )

    local any_missing=false
    for col in "${expected_cols[@]}"; do
        if ! echo "$header" | grep -qF "$col"; then
            log_warn "Expected column '$col' not found in annovar output — gnomAD column names may have changed"
            any_missing=true
        fi
    done

    if [ "$any_missing" = true ]; then
        log_warn "Verify that combine_annotations() column offsets still match the annovar output header"
    fi
}

run_vep() {
    local vcf="$1"
    local sample=$(basename "$vcf" .vcf)

    [ -f "$sample.vep.txt" ] && return 0

    if ! command -v vep &> /dev/null; then
        log_warn "VEP not found, skipping"
        return 0
    fi

    log_info "Starting VEP for $sample"

    local vep_log="$sample.vep.log"

    vep -i "$vcf" \
        --dir_cache "$VEP_CACHE" \
        --cache \
        --assembly GRCh38 \
        --offline \
        --fasta "$HG38_FASTA" \
        --everything \
        --force_overwrite \
        --tab \
        --fork 8 \
        --refseq \
        --pick \
        --exclude_predicted \
        --no_escape \
        --use_given_ref \
        -o "$sample.vep.output.txt" 2>"$vep_log"

    rm -f "${sample}.vep.output.txt_summary.html"
    grep -v "##" "$sample.vep.output.txt" > "$sample.vep.txt"
    rm -f "$sample.vep.output.txt"

    # Surface any errors from the VEP log
    if grep -qiE "^ERROR|^FATAL|failed|error" "$vep_log" 2>/dev/null; then
        log_warn "VEP reported issues for $sample:"
        grep -iE "^ERROR|^FATAL|failed|error" "$vep_log" | head -5 | while IFS= read -r line; do
            log_warn "  $line"
        done
    fi
    rm -f "$vep_log"

    log_success "VEP completed for $sample"
}

run_snpeff() {
    local vcf="$1"
    local sample=$(basename "$vcf" .vcf)

    [ -f "$sample.snpEff.txt" ] && return 0

    log_info "Starting snpEff for $sample"

    local snpEff="$SNPEFF_DIR/snpEff.jar"
    local SnpSift="$SNPEFF_DIR/SnpSift.jar"
    local scriptsDir="$SNPEFF_DIR/scripts"
    local snpeff_log="$sample.snpEff.log"
    > "$snpeff_log"

    # Run snpEff for HG38
    java -Xmx2g -jar "$snpEff" GRCh38.p13.RefSeq \
        -canon -onlyProtein -strict -noShiftHgvs "$vcf" \
        > "$sample.snpEff.ref.vcf" 2>>"$snpeff_log"

    # Split into one effect per line
    cat "$sample.snpEff.ref.vcf" | "$scriptsDir/vcfEffOnePerLine.pl" \
        > "$sample.snpEff.1Eff.vcf"

    # Filter out upstream/downstream/intragenic
    cat "$sample.snpEff.1Eff.vcf" | \
        java -jar "$SnpSift" filter -n \
        "(ANN[*].EFFECT has 'upstream_gene_variant') | \
         (ANN[*].EFFECT has 'downstream_gene_variant') | \
         (ANN[*].EFFECT has 'intragenic_variant')" 2>>"$snpeff_log" \
        > "$sample.snpEff.filter.vcf"

    # Combine and sort
    cat "$sample.snpEff.filter.vcf" \
        <(awk 'FNR==NR{a[$1"_"$2"_"$4"_"$5]=$0;next}{if(!($1"_"$2"_"$4"_"$5 in a))print}' \
        <(grep -v "^#" "$sample.snpEff.filter.vcf") \
        <(grep -v "^#" "$sample.snpEff.ref.vcf")) | vcf-sort -c 2>>"$snpeff_log" \
        > "$sample.snpEff.vcf"

    # Extract fields
    java -jar "$SnpSift" extractFields \
        -s "," -e "." "$sample.snpEff.vcf" \
        CHROM POS REF ALT FILTER AF AC DP MQ \
        "ANN[*].GENE" "ANN[*].FEATUREID" "ANN[*].HGVS_C" "ANN[*].HGVS_P" \
        "ANN[*].ALLELE" "ANN[*].EFFECT" "ANN[*].IMPACT" "ANN[*].BIOTYPE" "ANN[*].RANK" \
        "ANN[*].CDNA_POS" "ANN[*].CDNA_LEN" "ANN[*].CDS_POS" "ANN[*].CDS_POS" \
        "ANN[*].AA_POS" "ANN[*].AA_LEN" \
        "LOF[*].GENE" "LOF[*].NUMTR" "LOF[*].PERC" 2>>"$snpeff_log" \
        | sed 's/ANN\[\*\]\.//g' \
        > "$sample.presnpEff.txt"

    # Match to VCF order
    cat \
        <(awk -F"\t" '{if(NR==1)print}' "$sample.presnpEff.txt") \
        <(awk -F"\t" 'NR==FNR{a[$1"_"$2"_"$3"_"$4]=$0;next}($1"_"$2"_"$4"_"$5 in a){print a[$1"_"$2"_"$4"_"$5]}' \
        "$sample.presnpEff.txt" <(grep -v "^#" "$vcf")) \
        > "$sample.snpEff.txt"

    rm -f "$sample.snpEff.ref.vcf" "$sample.snpEff.1Eff.vcf" \
          "$sample.snpEff.filter.vcf" "$sample.snpEff.vcf" "$sample.presnpEff.txt"

    # Surface any errors from the snpEff log (exclude routine INFO/WARNING lines)
    if grep -qiE "^ERROR|Exception|OutOfMemory" "$snpeff_log" 2>/dev/null; then
        log_warn "snpEff reported issues for $sample:"
        grep -iE "^ERROR|Exception|OutOfMemory" "$snpeff_log" | head -5 | while IFS= read -r line; do
            log_warn "  $line"
        done
    fi
    rm -f "$snpeff_log"

    log_success "snpEff completed for $sample"
}

run_transvar() {
    local vcf="$1"
    local sample=$(basename "$vcf" .vcf)

    [ -f "$sample.transvar.txt" ] && return 0

    if ! command -v transvar &> /dev/null; then
        log_warn "TransVar not found, skipping"
        return 0
    fi

    log_info "Starting TransVar for $sample"

    mkdir -p transvar

    # Run transvar for HG38
    transvar ganno --reference "$HG38_FASTA" --refversion hg38 \
        --vcf "$vcf" --refseq --aa3 --noheader 2>/dev/null | \
        awk '{if($1!~/^#/)print}' | awk '{if($11!~/^X/)print}' \
        > "./transvar/$sample.transvar.vcf"

    # Extract useful fields
    paste \
        <(awk '{if($1!~/^##/)print}' "./transvar/$sample.transvar.vcf" | cut -f1-2,4-5) \
        <(awk '{if($1!~/^##/)print}' "./transvar/$sample.transvar.vcf" | rev | cut -f3-6 | rev) \
        | sed 's/\//\t/g' | awk '{if($5!~/^X/)print}' | sed 's/[[:space:]](protein_coding)//g' \
        > "$sample.noX.txt"

    # Remove version numbers
    awk '{print $5}' "$sample.noX.txt" | cut -d"." -f1 > "$sample.noX.noV.txt"

    # Replace transcripts
    paste \
        <(cut -f1-4 "$sample.noX.txt") \
        <(cut -f1 "$sample.noX.noV.txt") \
        <(cut -f6- "$sample.noX.txt") \
        > "$sample.noX2.txt"

    # Get transcript sizes
    if [ -f "$REFSEQ_TRANSCRIPTS" ]; then
        awk -F"\t" 'NR==FNR{a[$1]=$7;next}{if(($5 in a))print $0"\t"a[$5];else print $0"\t-"}' \
            "$REFSEQ_TRANSCRIPTS" "$sample.noX2.txt" \
            > "$sample.noX.size.txt"
    else
        awk '{print $0"\t-"}' "$sample.noX2.txt" > "$sample.noX.size.txt"
    fi

    # Get VCF positions
    awk '{if($1!~/^#/)print}' "$vcf" | cut -f1-2,4-5 > "$sample.noheaderVCF.txt"

    # Find longest transcript per variant
    awk '{
        if ( arr[$1"_"$2"_"$3"_"$4] == "" ) {
            arr[$1"_"$2"_"$3"_"$4] = $11
        }
        if ( arr[$1"_"$2"_"$3"_"$4] != "" ) {
            if ( arr[$1"_"$2"_"$3"_"$4] <= $11 ) { arr[$1"_"$2"_"$3"_"$4] = $11 }
        }
    }
    END { for (x in arr) print x"\t"arr[x] }' "$sample.noX.size.txt" \
        | sed 's/\_/\t/g' \
        > "$sample.longTrans.unsort.txt"

    # Order by VCF order
    awk -F"\t" 'NR==FNR{a[$1"\t"$2"\t"$3"\t"$4]=$0;next}{if(($1"\t"$2"\t"$3"\t"$4 in a))print a[$1"\t"$2"\t"$3"\t"$4];else print $1"\t"$2"\t"$3"\t"$4"\t-"}' \
        "$sample.longTrans.unsort.txt" "$sample.noheaderVCF.txt" \
        > "$sample.longTrans.txt"

    # Final output
    echo -e "Chr\tPos\tRef\tAlt\tTranscript\tGene\tStrand\tHGVSg\tHGVSc\tHGVSp\tLength" \
        > "$sample.transvar.txt"
    awk -F"\t" 'NR==FNR{a[$1"\t"$2"\t"$3"\t"$4"\t"$11]=$0;next}{if(($0 in a))print a[$0];else print $1"\t"$2"\t"$3"\t"$4"\t-\t-\t-\t-\t-\t-\t-"}' \
        "$sample.noX.size.txt" "$sample.longTrans.txt" \
        | sed 's/chr[[:alnum:]]*\://g' \
        | sed "s/\(p.*\)X/\1Ter/g" \
        >> "$sample.transvar.txt"

    rm -f "$sample.noX.size.txt" "$sample.noX.txt" "$sample.noX2.txt" \
          "$sample.noX.noV.txt" "$sample.noheaderVCF.txt" \
          "$sample.longTrans.txt" "$sample.longTrans.unsort.txt"

    log_success "TransVar completed for $sample"
}

run_cancervar() {
    local vcf="$1"
    local sample=$(basename "$vcf" .vcf)

    [ -f "$sample.CancerVar.txt" ] && return 0

    if [ ! -f "$CANCERVAR_FAST" ]; then
        log_warn "CancerVar-fast not found, skipping"
        return 0
    fi

    log_info "Starting CancerVar-fast for $sample"

    python3 "$CANCERVAR_FAST" "$vcf" -o "$sample.CancerVar.txt"

    log_success "CancerVar-fast completed for $sample"
}

run_sg10k() {
    local vcf="$1"
    local sample=$(basename "$vcf" .vcf)

    [ -f "$sample.SG10k.txt" ] && return 0
    [ ! -f "$SG10K_DB" ] && { log_warn "SG10K database not found, skipping"; return 0; }

    log_info "Starting SG10K annotation for $sample"

    awk '{if($1!~/^#/)print $1"\t"$2"\t"$4"\t"$5}' "$vcf" > "$sample.noheader.vcf"

    awk -F"\t" 'NR==FNR{a[$1"_"$2"_"$3"_"$4]=$0;next}{if(($1"_"$2"_"$3"_"$4 in a))print a[$1"_"$2"_"$3"_"$4];else print $1"\t"$2"\t"$3"\t"$4"\t-\t-\t-\t-\t-\t-\t-\t-"}' \
        "$SG10K_DB" "$sample.noheader.vcf" \
        > "$sample.SG10k.txt"

    sed -i '1s/^/CHR\tBP.B38\tREF\tALT\tAN_All\tAF_All\tAN_CHS\tAF_CHS\tAN_INS\tAF_INS\tAN_MAS\tAF_MAS\n/' "$sample.SG10k.txt"

    rm -f "$sample.noheader.vcf"

    log_success "SG10K completed for $sample"
}

run_genomeasia() {
    local vcf="$1"
    local sample=$(basename "$vcf" .vcf)

    [ -f "$sample.genomeAsia.txt" ] && return 0
    [ ! -f "$GENOMEASIA_DB" ] && { log_warn "GenomeAsia database not found, skipping"; return 0; }

    log_info "Starting GenomeAsia annotation for $sample"

    awk -F"\t" 'NR==FNR{a[$1"_"$2"_"$3"_"$4]=$0;next}{if($1"_"$2"_"$3"_"$4 in a)print a[$1"_"$2"_"$3"_"$4];else print $1"\t"$2"\t"$3"\t"$4"\t-\t-\t-\t-\t-\t-\t-\t-\t-\t-\t-\t-"}' \
        "$GENOMEASIA_DB" \
        <(grep -v "^#" "$vcf" | cut -f1,2,4,5) | \
        sort -k1,1V -k2,2n | \
        sed '1s/^/CHR\tPOS\tREF\tALT\tSEA_AN\tSEA_AC\tSEA_AF\tSEA_HOM\tNEA_AN\tNEA_AC\tNEA_AF\tNEA_HOM\tSAS_AN\tSAS_AC\tSAS_AF\tSAS_HOM\n/' \
        > "$sample.genomeAsia.txt"

    log_success "GenomeAsia completed for $sample"
}

run_annocheck() {
    local vcf="$1"
    local sample=$(basename "$vcf" .vcf)

    [ -f "$sample.annoCheck.txt" ] && return 0

    for f in "$sample.transvar.txt" "$sample.annovar.txt" "$sample.vep.txt" "$sample.snpEff.txt"; do
        [ ! -f "$f" ] && return 0
    done

    log_info "Running annotation concordance check for $sample"

    paste \
        <(cut -f1-4,5,6,9-10 "$sample.transvar.txt" | sed '1c Chr\tPos\tRef\tAlt\tTrans.Tvar\tGene.Tvar\tHGVSc.Tvar\tHGVSp.Tvar') \
        <(cut -f6,7,9 "$sample.annovar.txt" | sed 's/\./\-/g' | sed '1c Loc.Ann\tGene.Ann\tType.Ann') \
        <(cut -f19,5,43-44,7 "$sample.vep.txt" | awk '{gsub("-",":-",$5)}1' | awk '{gsub(/\..*$/,"",$1)}1' | sed 's/ /\t/g' | sed 's/:/\t/g' | cut -f1-3,5,7 | sed '1c Trans.Vep\tType.Vep\tGene.Vep\tHGVSc.Vep\tHGVSp.Vep') \
        <(cut -f10-13,15 "$sample.snpEff.txt" | awk '{gsub(/\..*$/,"",$2)}1' | sed 's/ /\t/g' | sed '1c Gene.SpEf\tTrans.SpEf\tHGVSc.SpEf\tHGVSp.SpEf\tType.SpEf') \
        > "$sample.PreCheck.txt"

    paste \
        <(cut -f1-4 "$sample.PreCheck.txt") \
        <(awk -F"\t" '{print $6"\t"$10"\t"$14"\t"$17"\t"$5"\t"$12"\t"$18"\t"$7"\t"$15"\t"$19"\t"$8"\t"$16"\t"$20"\t"$9"\t"$11"\t"$13"\t"$21}' "$sample.PreCheck.txt") \
        > "$sample.annoCheck.txt"

    rm -f "$sample.PreCheck.txt"

    log_success "AnnoCheck completed for $sample"
}

# =============================================================================
# COMPARISON FUNCTION
# =============================================================================

run_compare() {
    local sample_vcf="$1"
    local vcf_dir="$2"
    local name="$3"
    local sample=$(basename "$sample_vcf" .vcf)

    [ -f "$sample.compare$name.txt" ] && return 0
    [ ! -d "$vcf_dir" ] && { log_warn "Compare directory $vcf_dir not found"; return 0; }

    log_info "Comparing $sample with $name samples"

    mkdir -p "$sample.compare$name"

    # Compare with each VCF in directory
    for file in "$vcf_dir"/*.vcf; do
        [ ! -f "$file" ] && continue
        local filename=$(basename "$file" .vcf)
        awk 'FNR==NR{a[$1"_"$2"_"$4"_"$5]=$5;next}{if(($1"_"$2"_"$3"_"$4 in a))print a[$1"_"$2"_"$3"_"$4];else print"-"}' \
            "$file" \
            <(grep -v "^#" "$sample_vcf" | cut -f1-2,4-5) \
            > "./$sample.compare$name/$filename.out"
    done

    # Concatenate results
    paste \
        <(grep -v "^#" "$sample_vcf" | cut -f1-2,4-5 | sed '1i #Chr\tPos\tRef\tAlt') \
        <(cat <(echo "$vcf_dir"/*.VCFstats.txt 2>/dev/null | sed 's/.VCFstats.txt//g' | sed "s|$vcf_dir\/||g" | sed -r "s/\s+/\t/g") \
        <(paste "./$sample.compare$name"/*.out 2>/dev/null)) \
        > "$sample.precompare$name.txt" 2>/dev/null || true

    # Get field count
    local field=$(cut -f5- "$sample.precompare$name.txt" 2>/dev/null | awk '{print NF}' | sort | uniq | head -1)

    # Add count column
    paste \
        <(cut -f1-4 "$sample.precompare$name.txt") \
        <(grep -v "^#" "$sample.precompare$name.txt" | cut -f4- | awk '{print gsub($1,"")-1}' | sed "1i ${name}${field}") \
        <(cut -f5- "$sample.precompare$name.txt") \
        > "$sample.compare$name.txt" 2>/dev/null || true

    # Compare VAF
    for file2 in "$vcf_dir"/*.VCFstats.txt; do
        [ ! -f "$file2" ] && continue
        local filename2=$(basename "$file2" .VCFstats.txt)
        awk -F"\t" 'FNR==NR{a[$1"_"$2"_"$3"_"$4]=$9;next}{if(($1"_"$2"_"$3"_"$4 in a))print a[$1"_"$2"_"$3"_"$4]; else print "-"}' \
            "$file2" \
            <(grep -v "^#" "$sample_vcf" | cut -f1-2,4-5) \
            > "./$sample.compare$name/$filename2.out2"
    done

    paste \
        <(grep -v "^#" "$sample_vcf" | cut -f1-2,4-5 | sed '1i #Chr\tPos\tRef\tAlt') \
        <(cat <(echo "$vcf_dir"/*.VCFstats.txt 2>/dev/null | sed 's/.VCFstats.txt//g' | sed "s|$vcf_dir\/||g" | sed -r "s/\s+/\t/g") \
        <(paste "./$sample.compare$name"/*.out2 2>/dev/null)) \
        > "$sample.compareVF$name.txt" 2>/dev/null || true

    # Cleanup
    rm -f "$sample.precompare$name.txt"
    rm -rf "$sample.compare$name"

    log_success "Compare $name completed for $sample"
}

# =============================================================================
# MAIN PIPELINE
# =============================================================================

merge_vcfs() {
    local sample="Merge"

    [ -f "$sample.vcf" ] && return 0

    log_step "MERGING VCFs"

    ls *.vcf | grep -v "^Merge" > VCFlist.txt

    # Sort and compress each VCF in parallel
    parallel --memsuspend "$MEM_SUSPEND" "[ -f {.}.sort.gz ] || \
        (bgzip -c <(vcf-sort -c <(bcftools view -a --min-ac=1 --no-update {})) > {.}.sort.gz ; \
        tabix -p vcf {.}.sort.gz)" :::: VCFlist.txt

    # Merge
    vcf-merge -c none -s $(ls *.sort.gz | tr '\n' ' ') | vcf-sort -c > "$sample.vcf"

    rm -f *.sort.gz *.sort.gz.tbi

    log_success "VCF merging completed"
}

run_annotations_parallel() {
    local sample="Merge"

    [ -f "$sample.AnnoAll.txt" ] && return 0

    log_step "RUNNING ANNOTATIONS IN PARALLEL"

    export -f run_annovar run_vep run_snpeff run_transvar verify_annovar_columns log_info log_success log_warn
    export ANNOVAR_FAST CANCERVAR_FAST SNPEFF_DIR VEP_CACHE HG38_FASTA REFSEQ_TRANSCRIPTS

    log_info "Starting parallel annotation (ANNOVAR, VEP, snpEff, TransVar)..."

    (
        run_annovar "$sample.vcf" &
        run_vep "$sample.vcf" &
        run_snpeff "$sample.vcf" &
        run_transvar "$sample.vcf" &
        wait
    )

    log_success "Core annotations completed"

    log_info "Running CancerVar..."
    run_cancervar "$sample.vcf"

    log_info "Running database lookups in parallel (SG10K, GenomeAsia)..."
    (
        run_sg10k "$sample.vcf" &
        run_genomeasia "$sample.vcf" &
        wait
    )

    run_annocheck "$sample.vcf"

    log_success "All annotations completed"
}

run_comparisons_parallel() {
    local sample="Merge"

    [ -f "$sample.compare.txt" ] && return 0

    log_step "RUNNING COMPARISONS IN PARALLEL"
    log_info "Comparing against: ${COMPARE_NAMES[*]}"

    (
        for i in "${!COMPARE_DBS[@]}"; do
            run_compare "$sample.vcf" "${COMPARE_DBS[$i]}" "${COMPARE_NAMES[$i]}" &
        done
        wait
    )

    # Combine compare files
    local name0="${COMPARE_NAMES[0]}"
    local name1="${COMPARE_NAMES[1]}"

    if [ -f "$sample.compare${name0}.txt" ]; then
        paste \
            <(cut -f1-5 "$sample.compare${name0}.txt") \
            <(cut -f5 "$sample.compare${name1}.txt" 2>/dev/null || echo "") \
            <(cut -f6- "$sample.compare${name0}.txt") \
            <(cut -f6- "$sample.compare${name1}.txt" 2>/dev/null || echo "") \
            > "$sample.compare.txt" 2>/dev/null || true
        rm -f "$sample.compare${name0}.txt" "$sample.compare${name1}.txt"
    fi

    # Combine VAF compare files
    if [ -f "$sample.compareVF${name0}.txt" ]; then
        paste \
            <(cut -f1- "$sample.compareVF${name0}.txt") \
            <(cut -f5- "$sample.compareVF${name1}.txt" 2>/dev/null || echo "") \
            > "$sample.compareVAF.txt" 2>/dev/null || true
        rm -f "$sample.compareVF${name0}.txt" "$sample.compareVF${name1}.txt"
    fi

    log_success "Comparisons completed"
}

combine_annotations() {
    local sample="Merge"

    [ -f "$sample.AnnoAll.txt" ] && return 0

    log_step "COMBINING ANNOTATIONS"

    # Combine annotations for HG38.
    # Columns are selected by HEADER NAME via cols_by_name() so the combined output
    # is resilient to column additions or reordering in upstream tool outputs.
    # The listing order within each cols_by_name call defines the output column order
    # and must be kept consistent with the positional assumptions in filter_anno_iseq():
    #   annotation.txt col 22 = ExonicFunc.refGene
    #   annotation.txt col 23 = Func.ensGene
    #   annotation.txt col 25 = Consequence (VEP)
    #   annotation.txt col 12 = DP
    #   annotation.txt col 14 = VAF
    if [ -f "$sample.annovar.txt" ] && [ -f "$sample.snpEff.txt" ] && [ -f "$sample.transvar.txt" ]; then
        paste \
            <(grep -v "^#" "$sample.vcf" | cut -f1-2,4-5 | sed 's/:\S*//g' | sed '1i Chr\tPos\tRef\tAlt') \
            <(cols_by_name "$sample.snpEff.txt"   "GENE") \
            <(cols_by_name "$sample.transvar.txt" "Transcript" "HGVSg" "HGVSc" "HGVSp") \
            <(cols_by_name "$sample.annovar.txt"  "snp141") \
            <(cols_by_name "$sample.CancerVar.txt" "cosmic91" | sed 's/ID=//g') \
            <(cols_by_name "$sample.CancerVar.txt" "CancerVar: CancerVar and Evidence" \
                | sed 's/^CancerVar: //; s/ CancerVar: //g') \
            <(cut -f5-6 "$sample.compare.txt" 2>/dev/null || echo "") \
            <(cols_by_name "$sample.snpEff.txt"   "FILTER") \
            <(cols_by_name "$sample.annovar.txt"  \
                "ExonicFunc.refGene" "Func.ensGene" "cytoBand") \
            <(cols_by_name "$sample.vep.txt"      \
                "Consequence" "STRAND" "VARIANT_CLASS" "EXON" "INTRON") \
            <(cols_by_name "$sample.SG10k.txt"    \
                "AF_All" "AF_CHS" "AF_INS" "AF_MAS") \
            <(cols_by_name "$sample.genomeAsia.txt" \
                "SEA_AF" "NEA_AF" "SAS_AF") \
            <(cols_by_name "$sample.annovar.txt"  \
                "esp6500siv2_all" \
                "ExAC_ALL" "ExAC_AFR" "ExAC_AMR" "ExAC_EAS" \
                "ExAC_FIN" "ExAC_NFE" "ExAC_OTH" "ExAC_SAS" \
                "1000g2015aug_all" "1000g2015aug_afr" "1000g2015aug_eas" \
                "1000g2015aug_amr" "1000g2015aug_eur" "1000g2015aug_sas" \
                "Kaviar_AF" "Kaviar_AC" "Kaviar_AN" \
                "gnomad41_exome_AF" \
                "gnomad41_exome_AF_afr" "gnomad41_exome_AF_sas" \
                "gnomad41_exome_AF_amr" "gnomad41_exome_AF_eas" \
                "gnomad41_exome_AF_nfe" "gnomad41_exome_AF_fin" \
                "gnomad41_exome_AF_asj" "gnomad41_exome_AF_remaining" \
                "gnomad41_genome_AF" \
                "gnomad41_genome_AF_afr" \
                "gnomad41_genome_AF_amr" "gnomad41_genome_AF_asj" \
                "gnomad41_genome_AF_eas" "gnomad41_genome_AF_fin" \
                "gnomad41_genome_AF_nfe" "gnomad41_genome_AF_remaining") \
            <(cols_by_name "$sample.annovar.txt"  \
                "HRC_AF" "HRC_AC" "HRC_AN" \
                "HRC_non1000G_AF" "HRC_non1000G_AC" "HRC_non1000G_AN" \
                "GME_AF" "GME_NWA" "GME_NEA" "GME_AP" \
                "GME_Israel" "GME_SD" "GME_TP" "GME_CA" \
                "cg69" "nci60") \
            <(cols_by_name "$sample.annovar.txt"  \
                "InterVar_automated" \
                "PVS1" "PS1" "PS2" "PS3" "PS4" \
                "PM1" "PM2" "PM3" "PM4" "PM5" "PM6" \
                "PP1" "PP2" "PP3" "PP4" "PP5" \
                "BA1" "BS1" "BS2" "BS3" "BS4" \
                "BP1" "BP2" "BP3" "BP4" "BP5" "BP6" "BP7" \
                "CLNALLELEID" "CLNDN" "CLNDISDB" "CLNREVSTAT" "CLNSIG") \
            <(cols_by_name "$sample.annovar.txt"  \
                "MCAP" "REVEL" \
                "SIFT_score" "SIFT_pred" \
                "Polyphen2_HDIV_score" "Polyphen2_HDIV_pred" \
                "Polyphen2_HVAR_score" "Polyphen2_HVAR_pred" \
                "LRT_score" "LRT_pred" \
                "MutationTaster_score" "MutationTaster_pred" \
                "MutationAssessor_score" "MutationAssessor_pred" \
                "FATHMM_score" "FATHMM_pred" \
                "MetaSVM_score" "MetaSVM_pred" \
                "MetaLR_score" "MetaLR_pred" \
                "VEST4_score" "CADD_raw" "CADD_phred" \
                "GERP++_RS" \
                "phyloP30way_mammalian" "phyloP100way_vertebrate" "SiPhy_29way_logOdds" \
                "phastConsElements30way" "phastConsElements100way" "targetScanS") \
            > "$sample.Anno1.txt" 2>/dev/null || true

        # Fix IKZF1 annotations
        if [ -f "$sample.Anno1.txt" ] && [[ "$DO_IKZF1_FIX" == true ]]; then
            log_info "Applying IKZF1 annotation fix"
            paste \
                <(awk '{if($5=="IKZF1")print}' "$sample.Anno1.txt" | cut -f1-5) \
                <(awk '{if($10=="IKZF1")print}' "$sample.snpEff.txt" | cut -f11) \
                <(awk '{if($5=="IKZF1")print}' "$sample.Anno1.txt" | cut -f7) \
                <(awk '{if($10=="IKZF1")print}' "$sample.snpEff.txt" | cut -f12-13) \
                <(awk '{if($5=="IKZF1")print}' "$sample.Anno1.txt" | cut -f10-) \
                > "$sample.ReplaceAnno.txt" 2>/dev/null || true

            cat \
                <(awk '{if(NR==1)print}' "$sample.Anno1.txt") \
                <(cat <(awk '{if(NR!=1)print}' "$sample.Anno1.txt" | awk '{if($5!="IKZF1")print}') \
                <(cat "$sample.ReplaceAnno.txt" 2>/dev/null) | sort -k1,1V -k2,2n) \
                > "$sample.AnnoAll.txt"

            rm -f "$sample.Anno1.txt" "$sample.ReplaceAnno.txt"
        else
            mv "$sample.Anno1.txt" "$sample.AnnoAll.txt"
        fi
    fi

    log_success "Annotations combined"
}

extract_per_sample() {
    local sample="Merge"

    log_step "EXTRACTING PER-SAMPLE ANNOTATIONS"

    export -f vcf_stats
    parallel --memsuspend "$MEM_SUSPEND" "vcf_stats {}" :::: VCFlist.txt

    if [ -f "$sample.AnnoAll.txt" ]; then
        parallel --memsuspend "$MEM_SUSPEND" "[ -f {.}.annotation.txt ] || \
            (awk '{if(NR==1)print}' $sample.AnnoAll.txt > {.}.Anno.txt; \
            awk -F\"\t\" 'NR==FNR{a[\$1\"_\"\$2\"_\"\$3\"_\"\$4]=\$0;next}(\$1\"_\"\$2\"_\"\$4\"_\"\$5 in a){print a[\$1\"_\"\$2\"_\"\$4\"_\"\$5]}' \
            $sample.AnnoAll.txt {} >> {.}.Anno.txt; \
            paste \
            <(cut -f1-4 {.}.Anno.txt) \
            <(cut -f5 {.}.VCFstats.txt) \
            <(cut -f5-9 {.}.Anno.txt) \
            <(cut -f6-9 {.}.VCFstats.txt) \
            <(cut -f10- {.}.Anno.txt | sed 's/Name=//g') \
            >{.}.Anno2.txt; \
            paste \
            <(cut -f1-15 {.}.Anno2.txt) \
            <(awk -F\"\t\" '{print \$6\":\"\$1\"(GRCh38):\"\$8\"; \"\$7\"(\"\$6\"):\"\$9\";\"\$10\"(\"int(\$14*100+0.5)\"% VAF)\"}' {.}.Anno2.txt) \
            <(cut -f16- {.}.Anno2.txt) \
            >{.}.annotation.txt; \
            rm {.}.Anno.txt {.}.Anno2.txt)" :::: VCFlist.txt
    fi

    if [ -f "$sample.compare.txt" ]; then
        parallel --memsuspend "$MEM_SUSPEND" "[ -f {.}.compare.txt ] || \
            (awk '{if(NR==1)print}' $sample.compare.txt > {.}.compare.txt; \
            awk -F\"\t\" 'NR==FNR{a[\$1\"_\"\$2\"_\"\$3\"_\"\$4]=\$0;next}(\$1\"_\"\$2\"_\"\$4\"_\"\$5 in a){print a[\$1\"_\"\$2\"_\"\$4\"_\"\$5]}' \
            $sample.compare.txt {} >> {.}.compare.txt)" :::: VCFlist.txt
    fi

    if [ -f "$sample.compareVAF.txt" ]; then
        parallel --memsuspend "$MEM_SUSPEND" "[ -f {.}.compareVAF.txt ] || \
            (awk '{if(NR==1)print}' $sample.compareVAF.txt > {.}.compareVAF.txt; \
            awk -F\"\t\" 'NR==FNR{a[\$1\"_\"\$2\"_\"\$3\"_\"\$4]=\$0;next}(\$1\"_\"\$2\"_\"\$4\"_\"\$5 in a){print a[\$1\"_\"\$2\"_\"\$4\"_\"\$5]}' \
            $sample.compareVAF.txt {} >> {.}.compareVAF.txt)" :::: VCFlist.txt
    fi

    if [ -f "$sample.annoCheck.txt" ]; then
        parallel --memsuspend "$MEM_SUSPEND" "[ -f {.}.annoCheck.txt ] || \
            (awk '{if(NR==1)print}' $sample.annoCheck.txt > {.}.annoCheck.txt; \
            awk -F\"\t\" 'NR==FNR{a[\$1\"_\"\$2\"_\"\$3\"_\"\$4]=\$0;next}(\$1\"_\"\$2\"_\"\$4\"_\"\$5 in a){print a[\$1\"_\"\$2\"_\"\$4\"_\"\$5]}' \
            $sample.annoCheck.txt {} >> {.}.annoCheck.txt)" :::: VCFlist.txt
    fi

    log_success "Per-sample extraction completed"
}

filter_and_combine() {
    log_step "FILTERING AND COMBINING"

    export -f filter_anno_iseq
    parallel --memsuspend "$MEM_SUSPEND" "filter_anno_iseq {.}.annotation.txt" :::: VCFlist.txt

    # Combine annotations
    [ -f Combine.annotation.txt ] || \
    (
        parallel sed -n \'1p\' {.}.annotation.txt :::: VCFlist.txt | sort | uniq | awk '{print "SAMPLE\t"$0}' \
        > Combine.header.annotation.txt
        parallel "awk '{if(NR!=1)print}' {.}.annotation.txt > {.}.body.annotation.txt" :::: VCFlist.txt
        parallel "awk '{print FILENAME,\"\t\"\$0}' {.}.body.annotation.txt" :::: VCFlist.txt | sed 's/.body.annotation.txt//g' \
        > Combine.body.annotation.txt
        cat Combine.header.annotation.txt Combine.body.annotation.txt > Combine.annotation.txt
        rm -f *.body.annotation.txt *.header.annotation.txt
    )

    # Combine Filter
    [ -f Combine.Filter.txt ] || \
    (
        parallel sed -n \'1p\' {.}.Filter.txt :::: VCFlist.txt | uniq | awk '{print "SAMPLE\t"$0}' \
        > Combine.header.Filter.txt
        parallel "awk '{if(NR!=1)print}' {.}.Filter.txt > {.}.body.Filter.txt" :::: VCFlist.txt
        parallel "awk '{print FILENAME,\"\t\"\$0}' {.}.body.Filter.txt" :::: VCFlist.txt | sed 's/.body.Filter.txt//g' \
        > Combine.body.Filter.txt
        cat Combine.header.Filter.txt Combine.body.Filter.txt > Combine.Filter.txt
        rm -f *.body.Filter.txt *.header.Filter.txt
    )

    # Combine compare
    [ -f Combine.compare.txt ] || \
    (
        parallel sed -n \'1p\' {.}.compare.txt :::: VCFlist.txt 2>/dev/null | uniq | awk '{print "SAMPLE\t"$0}' \
        > Combine.header.compare.txt
        parallel "awk '{if(NR!=1)print}' {.}.compare.txt > {.}.body.compare.txt" :::: VCFlist.txt 2>/dev/null || true
        parallel "awk '{print FILENAME,\"\t\"\$0}' {.}.body.compare.txt" :::: VCFlist.txt 2>/dev/null | sed 's/.body.compare.txt//g' \
        > Combine.body.compare.txt
        cat Combine.header.compare.txt Combine.body.compare.txt > Combine.compare.txt 2>/dev/null || true
        rm -f *.body.compare.txt *.header.compare.txt
    )

    # Combine compareVAF
    [ -f Combine.compareVAF.txt ] || \
    (
        parallel sed -n \'1p\' {.}.compareVAF.txt :::: VCFlist.txt 2>/dev/null | uniq | awk '{print "SAMPLE\t"$0}' \
        > Combine.header.compareVAF.txt
        parallel "awk '{if(NR!=1)print}' {.}.compareVAF.txt > {.}.body.compareVAF.txt" :::: VCFlist.txt 2>/dev/null || true
        parallel "awk '{print FILENAME,\"\t\"\$0}' {.}.body.compareVAF.txt" :::: VCFlist.txt 2>/dev/null | sed 's/.body.compareVAF.txt//g' \
        > Combine.body.compareVAF.txt
        cat Combine.header.compareVAF.txt Combine.body.compareVAF.txt > Combine.compareVAF.txt 2>/dev/null || true
        rm -f *.body.compareVAF.txt *.header.compareVAF.txt
    )

    # Combine annoCheck
    [ -f Combine.annoCheck.txt ] || cp Merge.annoCheck.txt Combine.annoCheck.txt 2>/dev/null || true

    log_success "Filtering and combining completed"
}

# =============================================================================
# EXCEL WRITER FUNCTION
# =============================================================================

write_sample_xlsx() {
    local vcf="$1"
    local sample=$(basename "$vcf" .vcf)

    [ -f "$sample.xlsx" ] && return 0

    perl - "$sample" <<'PERL_SCRIPT'
use strict;
use warnings;
use Excel::Writer::XLSX;

my $sample = $ARGV[0];
my $sampleName = $sample;
$sampleName =~ s/^(.{20}).*/$1/;

# Check required files exist
for my $ext (qw(Filter.txt annotation.txt annoCheck.txt compare.txt compareVAF.txt)) {
    next unless -f "$sample.$ext";
}

my $workbook = Excel::Writer::XLSX->new("$sample.xlsx");

# Filter worksheet
if (-f "$sample.Filter.txt") {
    open(FILTER, "$sample.Filter.txt") or die "$sample.Filter.txt: $!";
    my $filter = $workbook->add_worksheet("$sampleName.filter");
    my $row = 0;
    while (<FILTER>) {
        chomp;
        my @fields = split('\t', $_);
        my $col = 0;
        for my $c (@fields) { $filter->write($row, $col++, $c); }
        $row++;
    }
    close(FILTER);
}

# Annotation worksheet
if (-f "$sample.annotation.txt") {
    open(ANNOTATION, "$sample.annotation.txt") or die "$sample.annotation.txt: $!";
    my $annotation = $workbook->add_worksheet("$sampleName");
    my $row = 0;
    while (<ANNOTATION>) {
        chomp;
        my @fields = split('\t', $_);
        my $col = 0;
        for my $c (@fields) { $annotation->write($row, $col++, $c); }
        $row++;
    }
    close(ANNOTATION);
}

# Check worksheet
if (-f "$sample.annoCheck.txt") {
    open(CHECK, "$sample.annoCheck.txt") or die "$sample.annoCheck.txt: $!";
    my $check = $workbook->add_worksheet("$sampleName.check");
    my $row = 0;
    while (<CHECK>) {
        chomp;
        my @fields = split('\t', $_);
        my $col = 0;
        for my $c (@fields) { $check->write($row, $col++, $c); }
        $row++;
    }
    close(CHECK);
}

# Compare worksheet
if (-f "$sample.compare.txt") {
    open(COMPARE, "$sample.compare.txt") or die "$sample.compare.txt: $!";
    my $compare = $workbook->add_worksheet("$sampleName.comp");
    my $row = 0;
    while (<COMPARE>) {
        chomp;
        my @fields = split('\t', $_);
        my $col = 0;
        for my $c (@fields) { $compare->write($row, $col++, $c); }
        $row++;
    }
    close(COMPARE);
}

# CompareVAF worksheet
if (-f "$sample.compareVAF.txt") {
    open(COMPAREVAF, "$sample.compareVAF.txt") or die "$sample.compareVAF.txt: $!";
    my $compareVAF = $workbook->add_worksheet("$sampleName.compVF");
    my $row = 0;
    while (<COMPAREVAF>) {
        chomp;
        my @fields = split('\t', $_);
        my $col = 0;
        for my $c (@fields) { $compareVAF->write($row, $col++, $c); }
        $row++;
    }
    close(COMPAREVAF);
}

$workbook->close();
PERL_SCRIPT
}

export -f write_sample_xlsx

write_excel() {
    log_step "WRITING EXCEL OUTPUT"

    if ! perl -e 'use Excel::Writer::XLSX' 2>/dev/null; then
        log_warn "Excel::Writer::XLSX not found, skipping Excel output"
        return 0
    fi

    log_info "Writing Excel files"

    for vcf in $(cat VCFlist.txt); do
        write_sample_xlsx "$vcf"
    done

    # Write Combine.xlsx
    if [ -f Combine.Filter.txt ] && [ ! -f Combine.xlsx ]; then
        perl - "Combine" <<'PERL_SCRIPT'
use strict;
use warnings;
use Excel::Writer::XLSX;

my $sample = $ARGV[0];

my $workbook = Excel::Writer::XLSX->new("$sample.xlsx");

for my $ext (qw(Filter annotation compare compareVAF annoCheck)) {
    my $file = "$sample.$ext.txt";
    next unless -f $file;

    open(my $fh, "<", $file) or next;
    my $ws = $workbook->add_worksheet($ext);
    my $row = 0;
    while (<$fh>) {
        chomp;
        my @fields = split('\t', $_);
        my $col = 0;
        for my $c (@fields) { $ws->write($row, $col++, $c); }
        $row++;
    }
    close($fh);
}

$workbook->close();
PERL_SCRIPT
    fi

    log_success "Excel output completed"
}

# =============================================================================
# MAIN
# =============================================================================

main() {
    local start_time=$(date +%s)

    echo ""
    echo "=============================================================="
    echo "  OPTIMIZED VCF ANNOTATION PIPELINE (HG38)"
    echo "=============================================================="
    echo ""
    echo "  Mode:     $(echo $MODE | tr '[:lower:]' '[:upper:]')"
    echo "  Database: $VCF_DATABASE"
    echo "  Compare:  ${COMPARE_NAMES[*]}"
    echo ""
    echo "=============================================================="
    echo ""

    # Check for VCF files
    VCF_COUNT=$(ls *.vcf 2>/dev/null | grep -v "^Merge" | wc -l)
    if [ "$VCF_COUNT" -eq 0 ]; then
        log_error "No VCF files found in current directory"
        exit 1
    fi
    log_info "Found $VCF_COUNT VCF files"

    # Run pipeline
    merge_vcfs
    run_annotations_parallel
    run_comparisons_parallel
    combine_annotations
    extract_per_sample
    filter_and_combine
    write_excel

    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    local minutes=$((duration / 60))
    local seconds=$((duration % 60))

    echo ""
    echo "=============================================================="
    echo "  PIPELINE COMPLETED in ${minutes}m ${seconds}s"
    echo "=============================================================="
    echo ""
}

main "$@"
