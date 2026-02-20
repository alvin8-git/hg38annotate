#!/bin/bash
# =============================================================================
# processVCF-hg38.sh - VCF Processing Pipeline for iSeq (HG38)
# =============================================================================
# This script automates VCF processing for iSeq panels using HG38 reference.
# It uses the optimized parallel annotation pipeline.
#
# Usage: Run from the vcf directory containing VCF files
#   cd /path/to/analysis/vcf
#   ~/Shared/SCRIPTS/claude/hg38annotate/processVCF-hg38.sh
#
# Expected directory structure:
#   /path/to/analysis/
#   ├── vcf/                  <- Run script from here
#   │   ├── *.vcf            <- VCF files
#   │   └── annotation/      <- Created by script
#   ├── bam/                  <- BAM files for IGV
#   └── output/               <- Final output directory
#
# =============================================================================

set -e  # Exit on error

# =============================================================================
# CONFIGURATION
# =============================================================================

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Database paths (can be overridden by environment variables)
DATABASE_iSeq="${DATABASE_iSeq:-$HOME/Databases/iSeq/vcf-hg38}"

# =============================================================================
# HELPER FUNCTIONS
# =============================================================================

log_info() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] INFO: $1"
}

log_error() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $1" >&2
}

# =============================================================================
# VCFstats FUNCTION
# =============================================================================

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

# =============================================================================
# iSeq PROCESSING
# =============================================================================

process_iseq() {
    log_info "######################## PROCESSING iSeq (HG38) #########################"

    # Check for VCF files
    VCF_COUNT=$(ls *.vcf 2>/dev/null | grep -v "^Merge" | wc -l)
    if [ "$VCF_COUNT" -eq 0 ]; then
        log_error "No VCF files found in current directory"
        return 1
    fi
    log_info "Found $VCF_COUNT VCF files"

    # Rename files if >20 characters
    rename 's/^(.{20}).*.vcf/$1\.vcf/' *.vcf 2>/dev/null || true

    # Clean up VCF by using only PASS/SB variants
    log_info "Filtering VCFs (PASS/SB only)..."
    parallel "bcftools view -i \"(%FILTER='PASS'||%FILTER='SB')\" -o {.}.x.vcf {}; mv {.}.x.vcf {}" ::: $(ls *.vcf | grep -v "^Merge")

    # Create VCFstats files
    log_info "Creating VCFstats files..."
    for vcf in $(ls *.vcf | grep -v "^Merge"); do
        vcf_stats "$vcf"
    done

    # Check if sample in Database AND is not empty, else copy to Database
    log_info "Checking database for new samples..."
    if [ -d "$DATABASE_iSeq" ]; then
        parallel "[ ! -f $DATABASE_iSeq/{} -a -s {} ] && { echo \"{} absent in Database. Copying...\"; cp {.}.vcf {.}.VCFstats.txt $DATABASE_iSeq/; echo \"Done\"; } || true" ::: $(ls *.vcf | grep -v "^Merge")
    fi

    # Start annotation processing
    if [ ! -f Combine.xlsx ]; then
        log_info "Running mergeVCFannotation-optimized-hg38.sh..."
        bash "$SCRIPT_DIR/mergeVCFannotation-optimized-hg38.sh" iseq
    else
        log_info "Excel files already exist, skipping annotation..."
    fi

    # Move all files to annotation directory
    # Check for actual content, not just directory existence (entrypoint pre-creates the dir)
    if [ ! -f ./annotation/Combine.xlsx ]; then
        log_info "Moving annotation files to annotation directory..."
        mkdir -p ./annotation
        mv *.txt *.xlsx ./annotation/ 2>/dev/null || true
        mv transvar/ ./annotation/ 2>/dev/null || true
        mv Merge.* ./annotation/ 2>/dev/null || true
    fi

    log_info "iSeq processing complete"
}

# =============================================================================
# CREATE OUTPUT DIRECTORY
# =============================================================================

create_output() {
    log_info "######################## CREATING OUTPUT #########################"

    # Create output directory if it doesn't exist
    if [ ! -d ../output ]; then
        log_info "Creating output directory..."
        mkdir ../output
    fi

    # Copy xlsx files and move annotation directory
    if [ -d ./annotation ]; then
        log_info "Copying files to output..."
        cp ./annotation/*.xlsx ../output/ 2>/dev/null || true
        mv ./annotation ../output/ 2>/dev/null || true
    fi

    log_info "Output directory created"
}

# =============================================================================
# GENERATE IGV SNAPSHOTS
# =============================================================================

process_single_igv_sample() {
    local filter_file="$1"
    local bam_dir="$2"
    local igv_script="$3"
    local igv_jar="$4"
    local java8_path="$5"

    local sample_name=$(basename "$filter_file" .Filter.txt)
    local bed_file="IgvBed/${sample_name}.bed"

    # Find matching BAM file
    local bam_file=""
    for pattern in "$bam_dir/${sample_name}"*.bam "$bam_dir/"*"${sample_name}"*.bam; do
        if [ -f "$pattern" ]; then
            bam_file="$pattern"
            break
        fi
    done

    if [ -z "$bam_file" ] || [ ! -f "$bam_file" ]; then
        echo "[IGV] No BAM file found for $sample_name, skipping..."
        return 1
    fi

    # Create BED file from filtered variants (chr, start, end, name)
    # Uses naming convention: sample-chr_number-pos.png (matches iSeq convention)
    awk -F"\t" -v sample="$sample_name" 'NR>1 && $1!="" {
        chr=$1; pos=$2;
        # Strip "chr" prefix for naming
        gsub(/^chr/, "", chr);
        print $1"\t"pos"\t"pos"\t"sample"-"chr"-"pos".png"
    }' "$filter_file" > "$bed_file"

    # Check if BED file has any variants
    if [ ! -s "$bed_file" ]; then
        echo "[IGV] No variants in $sample_name, skipping..."
        rm -f "$bed_file"
        return 1
    fi

    local variant_count=$(wc -l < "$bed_file")
    echo "[IGV] Processing $sample_name ($variant_count variants)..."

    # Run IGV snapshot script with HG38 genome
    python3 "$igv_script" "$bam_file" \
        -r "$bed_file" \
        -o "SnapShots" \
        -g hg38 \
        -bin "$igv_jar" \
        -java "$java8_path" \
        -suffix "$sample_name" \
        -nf4 \
        -ht 500 \
        -mem 4000 2>&1

    if [ $? -eq 0 ]; then
        echo "[IGV] Completed $sample_name"
        return 0
    else
        echo "[IGV] Failed $sample_name"
        return 1
    fi
}

export -f process_single_igv_sample

generate_igv_snapshots() {
    log_info "######################## GENERATING IGV SNAPSHOTS #########################"

    local output_dir="../output"
    local igv_script="$SCRIPT_DIR/make_IGV_snapshots.py"
    local igv_jar="${IGV_JAR:-$HOME/Software/IGV-snapshot-automator/bin/IGV_2.3.81/igv.jar}"
    local java8_path="${JAVA8_PATH:-/usr/lib/jvm/java-8-openjdk-amd64/bin/java}"
    local bam_dir="../bam"

    # Check if IGV snapshot script exists
    if [ ! -f "$igv_script" ]; then
        log_error "IGV snapshot script not found: $igv_script"
        log_info "Skipping IGV snapshot generation..."
        return 0
    fi

    # Check if IGV JAR exists
    if [ ! -f "$igv_jar" ]; then
        log_error "IGV JAR not found: $igv_jar"
        log_info "Skipping IGV snapshot generation..."
        return 0
    fi

    # Check if xvfb-run is available
    if ! command -v xvfb-run &> /dev/null; then
        log_error "xvfb-run not found, skipping IGV snapshot generation"
        log_info "Install with: apt install xvfb"
        return 0
    fi

    # Check if Java 8 is available
    if [ ! -f "$java8_path" ]; then
        log_error "Java 8 not found at: $java8_path"
        log_info "IGV 2.3.81 requires Java 8. Install with: apt install openjdk-8-jdk"
        return 0
    fi

    # Check if BAM directory exists
    if [ ! -d "$bam_dir" ]; then
        log_info "BAM directory not found ($bam_dir), skipping IGV snapshots..."
        return 0
    fi

    cd "$output_dir"

    # Create IgvBed and SnapShots directories
    mkdir -p IgvBed SnapShots

    # Determine parallel jobs
    local max_jobs="${IGV_PARALLEL_JOBS:-0}"

    if [ "$max_jobs" -eq 0 ]; then
        local total_mem_gb=$(free -g | awk '/^Mem:/{print $2}')
        max_jobs=$((total_mem_gb / 5))
        [ "$max_jobs" -lt 1 ] && max_jobs=1
        [ "$max_jobs" -gt 4 ] && max_jobs=4
        log_info "Running up to $max_jobs IGV instances in parallel (auto: ${total_mem_gb}GB RAM)"
    else
        log_info "Running up to $max_jobs IGV instances in parallel"
    fi

    # Collect all filter files to process
    local filter_files=()

    if [ -d annotation ]; then
        for f in annotation/*.Filter.txt; do
            [ -f "$f" ] && filter_files+=("$f:$bam_dir")
        done
    fi

    if [ ${#filter_files[@]} -eq 0 ]; then
        log_info "No filter files found for IGV processing"
        cd - > /dev/null
        return 0
    fi

    log_info "Processing ${#filter_files[@]} sample(s)..."

    # Run in parallel
    printf '%s\n' "${filter_files[@]}" | \
        parallel -j "$max_jobs" --colsep ':' \
        "process_single_igv_sample {1} {2} '$igv_script' '$igv_jar' '$java8_path'" 2>&1 | \
        while read line; do
            echo "    $line"
        done

    # Count actual PNG files generated
    local png_count=$(ls SnapShots/*.png 2>/dev/null | wc -l)

    cd - > /dev/null

    if [ "$png_count" -gt 0 ]; then
        log_info "Generated $png_count IGV snapshot(s)"
        log_info "Snapshots available at: $output_dir/SnapShots/"
    else
        log_info "No IGV snapshots generated (no matching BAM files or variants)"
    fi
}

# =============================================================================
# GENERATE HTML REPORTS
# =============================================================================

generate_html_reports() {
    log_info "######################## GENERATING HTML REPORTS #########################"

    local output_dir="../output"
    local html_script="$SCRIPT_DIR/excel_to_html_report.py"

    # Check if HTML generation script exists
    if [ ! -f "$html_script" ]; then
        log_error "HTML generation script not found: $html_script"
        log_info "Skipping HTML report generation..."
        return 0
    fi

    # Check if python3 and openpyxl are available
    if ! command -v python3 &> /dev/null; then
        log_error "python3 not found, skipping HTML report generation"
        return 0
    fi

    if ! python3 -c "import openpyxl" 2>/dev/null; then
        log_error "openpyxl module not found. Install with: pip install openpyxl"
        log_info "Skipping HTML report generation..."
        return 0
    fi

    cd "$output_dir"

    # Recreate html_reports directory to remove stale files from previous runs
    rm -rf html_reports
    mkdir -p html_reports

    local xlsx_count=0
    for xlsx in $(ls *.xlsx 2>/dev/null | grep -v "^Combine" | grep -v "^Summary" | grep -v "^~"); do
        log_info "Generating HTML report for: $xlsx"

        local sample_name=$(basename "$xlsx" .xlsx)

        # Generate dashboard + variant pages in html_reports directory
        python3 "$html_script" "$xlsx" "html_reports" "SnapShots"

        if [ $? -eq 0 ]; then
            xlsx_count=$((xlsx_count + 1))
            log_info "  -> Generated: html_reports/${sample_name}.html"
        else
            log_error "  -> Failed to generate HTML for $xlsx"
        fi
    done

    # Generate Summary.html landing page
    if [ $xlsx_count -gt 0 ]; then
        log_info "Generating Summary.html landing page..."
        python3 "$html_script" --summary "html_reports"

        if [ $? -eq 0 ]; then
            log_info "  -> Generated: html_reports/Summary.html"
        else
            log_error "  -> Failed to generate Summary.html"
        fi
    fi

    cd - > /dev/null

    if [ $xlsx_count -gt 0 ]; then
        log_info "Generated HTML reports for $xlsx_count sample(s)"
        log_info "HTML reports available at: $output_dir/html_reports/"
        log_info "Open Summary.html to view all samples"
    else
        log_info "No Excel files found for HTML report generation"
    fi
}

# =============================================================================
# CHECKPOINT DETECTION FUNCTIONS
# =============================================================================

check_annotation_complete() {
    local output_dir="../output"
    if [ -d "$output_dir/annotation" ]; then
        local xlsx_count=$(ls "$output_dir/annotation"/*.xlsx 2>/dev/null | wc -l)
        if [ "$xlsx_count" -gt 0 ]; then
            return 0
        fi
    fi
    if [ -d "$output_dir" ]; then
        local xlsx_count=$(ls "$output_dir"/*.xlsx 2>/dev/null | wc -l)
        if [ "$xlsx_count" -gt 0 ]; then
            return 0
        fi
    fi
    return 1
}

check_igv_complete() {
    local output_dir="../output"
    if [ -d "$output_dir/SnapShots" ]; then
        local png_count=$(ls "$output_dir/SnapShots"/*.png 2>/dev/null | wc -l)
        if [ "$png_count" -gt 0 ]; then
            return 0
        fi
    fi
    return 1
}

check_html_complete() {
    local output_dir="../output"
    if [ -d "$output_dir/html_reports" ]; then
        local html_count=$(ls "$output_dir/html_reports"/*.html 2>/dev/null | wc -l)
        if [ "$html_count" -gt 1 ]; then
            return 0
        fi
    fi
    return 1
}

show_status() {
    echo ""
    echo "Pipeline Status:"
    echo "================"

    if check_annotation_complete; then
        local xlsx_count=$(ls ../output/*.xlsx 2>/dev/null | wc -l)
        echo "  [OK] Annotation complete ($xlsx_count Excel files)"
    else
        echo "  [ ] Annotation not complete"
    fi

    if check_igv_complete; then
        local png_count=$(ls ../output/SnapShots/*.png 2>/dev/null | wc -l)
        echo "  [OK] IGV snapshots complete ($png_count images)"
    else
        echo "  [ ] IGV snapshots not complete"
    fi

    if check_html_complete; then
        local html_count=$(ls ../output/html_reports/*.html 2>/dev/null | wc -l)
        echo "  [OK] HTML reports complete ($html_count files)"
    else
        echo "  [ ] HTML reports not complete"
    fi
    echo ""
}

# =============================================================================
# MAIN FUNCTION
# =============================================================================

main() {
    local start_time=$(date +%s)

    # Stage flags
    local run_annotation=false
    local run_igv=false
    local run_html=false
    local run_all=true
    local force=false
    local show_status_only=false

    # Parallel settings
    export IGV_PARALLEL_JOBS=0

    log_info "=========================================="
    log_info "VCF Processing Pipeline (iSeq - HG38)"
    log_info "=========================================="
    log_info "Working directory: $(pwd)"
    log_info "Script directory: $SCRIPT_DIR"

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --annotate|--annotation)
                run_annotation=true
                run_all=false
                ;;
            --igv|--snapshots)
                run_igv=true
                run_all=false
                ;;
            --html|--reports)
                run_html=true
                run_all=false
                ;;
            --from-igv)
                run_igv=true
                run_html=true
                run_all=false
                ;;
            --from-html)
                run_html=true
                run_all=false
                ;;
            --force|-f)
                force=true
                ;;
            --parallel|-j)
                shift
                export IGV_PARALLEL_JOBS="$1"
                ;;
            --serial)
                export IGV_PARALLEL_JOBS=1
                ;;
            --status)
                show_status_only=true
                ;;
            --check)
                log_info "Checking dependencies..."
                echo ""
                echo "System tools:"
                for cmd in bcftools parallel rename perl awk java python3 transvar vep bgzip tabix vcf-merge vcf-sort xvfb-run; do
                    if command -v "$cmd" &> /dev/null; then
                        echo "  $cmd: OK"
                    else
                        echo "  $cmd: MISSING"
                    fi
                done
                echo ""
                echo "Local scripts (in $SCRIPT_DIR):"
                for script in mergeVCFannotation-optimized-hg38.sh excel_to_html_report.py make_IGV_snapshots.py; do
                    if [ -f "$SCRIPT_DIR/$script" ]; then
                        echo "  $script: OK"
                    else
                        echo "  $script: MISSING"
                    fi
                done
                echo ""
                echo "Python modules:"
                if python3 -c "import openpyxl" 2>/dev/null; then
                    echo "  openpyxl: OK"
                else
                    echo "  openpyxl: MISSING (pip install openpyxl)"
                fi
                echo ""
                echo "IGV Snapshots:"
                local igv_jar="${IGV_JAR:-$HOME/Software/IGV-snapshot-automator/bin/IGV_2.3.81/igv.jar}"
                local java8="${JAVA8_PATH:-/usr/lib/jvm/java-8-openjdk-amd64/bin/java}"
                if [ -f "$igv_jar" ]; then
                    echo "  IGV JAR: OK ($igv_jar)"
                else
                    echo "  IGV JAR: MISSING ($igv_jar)"
                fi
                if [ -f "$java8" ]; then
                    echo "  Java 8: OK ($java8)"
                else
                    echo "  Java 8: MISSING (apt install openjdk-8-jdk)"
                fi
                echo ""
                echo "Databases:"
                for db in "$HOME/Databases/humandb" "$HOME/Databases/vep" "$HOME/Databases/hg38"; do
                    if [ -d "$db" ]; then
                        echo "  $db: OK"
                    else
                        echo "  $db: MISSING"
                    fi
                done
                exit 0
                ;;
            --help|-h)
                echo "Usage: $0 [options]"
                echo "  Run from the vcf directory containing VCF files"
                echo ""
                echo "Pipeline Stages:"
                echo "  1. Annotation  - Run ANNOVAR, VEP, snpEff, TransVar, CancerVar (HG38)"
                echo "  2. IGV         - Generate IGV snapshots from BAM files"
                echo "  3. HTML        - Generate HTML reports from Excel files"
                echo ""
                echo "Options:"
                echo "  (no options)    Run all stages (skip completed stages)"
                echo "  --status        Show pipeline completion status"
                echo "  --annotate      Run annotation stage only"
                echo "  --igv           Run IGV snapshot stage only"
                echo "  --html          Run HTML report stage only"
                echo "  --from-igv      Run from IGV stage onwards (IGV + HTML)"
                echo "  --from-html     Run HTML stage only (same as --html)"
                echo "  --force, -f     Force re-run even if stage is complete"
                echo "  --parallel N    Run N IGV instances in parallel (default: auto based on RAM)"
                echo "  --serial        Run IGV snapshots sequentially (same as --parallel 1)"
                echo "  --check         Check dependencies"
                echo "  --help          Show this help"
                echo ""
                echo "Examples:"
                echo "  $0                  # Run full pipeline, skip completed stages"
                echo "  $0 --status         # Check what stages are complete"
                echo "  $0 --from-igv       # Re-run IGV and HTML (annotation already done)"
                echo "  $0 --html --force   # Force regenerate HTML reports"
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                echo "Use --help for usage information"
                exit 1
                ;;
        esac
        shift
    done

    # Show status only
    if [ "$show_status_only" = true ]; then
        show_status
        exit 0
    fi

    # Determine which stages to run
    if [ "$run_all" = true ]; then
        run_annotation=true
        run_igv=true
        run_html=true
    fi

    # =========================================================================
    # STAGE 1: ANNOTATION
    # =========================================================================
    if [ "$run_annotation" = true ]; then
        if [ "$force" = true ] || ! check_annotation_complete; then
            log_info ">>> STAGE 1: ANNOTATION"

            # Process iSeq
            process_iseq

            # Create output directory and copy files
            create_output
        else
            log_info ">>> STAGE 1: ANNOTATION [SKIPPED - already complete]"
            log_info "    Use --force to re-run annotation"
        fi
    fi

    # =========================================================================
    # STAGE 2: IGV SNAPSHOTS
    # =========================================================================
    if [ "$run_igv" = true ]; then
        if ! check_annotation_complete; then
            log_error "Cannot run IGV stage: Annotation not complete"
            log_error "Run annotation first or use --annotate"
            exit 1
        fi

        if [ "$force" = true ] || ! check_igv_complete; then
            log_info ">>> STAGE 2: IGV SNAPSHOTS"

            generate_igv_snapshots
        else
            log_info ">>> STAGE 2: IGV SNAPSHOTS [SKIPPED - already complete]"
            log_info "    Use --force to re-run IGV snapshots"
        fi
    fi

    # =========================================================================
    # STAGE 3: HTML REPORTS
    # =========================================================================
    if [ "$run_html" = true ]; then
        if ! check_annotation_complete; then
            log_error "Cannot run HTML stage: Annotation not complete"
            log_error "Run annotation first or use --annotate"
            exit 1
        fi

        if [ "$force" = true ] || ! check_html_complete; then
            log_info ">>> STAGE 3: HTML REPORTS"

            generate_html_reports
        else
            log_info ">>> STAGE 3: HTML REPORTS [SKIPPED - already complete]"
            log_info "    Use --force to re-run HTML reports"
        fi
    fi

    local end_time=$(date +%s)
    local duration=$((end_time - start_time))

    log_info "=========================================="
    log_info "######################## DONE #########################"
    log_info "Pipeline completed in ${duration}s"

    # Show final status
    show_status

    log_info "=========================================="
}

# Run main function
main "$@"
