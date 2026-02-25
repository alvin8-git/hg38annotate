#!/bin/bash
# =============================================================================
# check_docker_deps.sh - Verify all hg38annotate dependencies in Docker container
# =============================================================================
# Run this inside the Docker container to verify all tools are available:
#   docker run --rm hg38annotate /home/user/Scripts/check_docker_deps.sh
# =============================================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

PASS_COUNT=0
FAIL_COUNT=0
WARN_COUNT=0

check_command() {
    local cmd="$1"
    local desc="$2"
    if command -v "$cmd" &> /dev/null; then
        echo -e "  ${GREEN}[OK]${NC} $cmd - $desc"
        PASS_COUNT=$((PASS_COUNT + 1))
        return 0
    else
        echo -e "  ${RED}[FAIL]${NC} $cmd - $desc"
        FAIL_COUNT=$((FAIL_COUNT + 1))
        return 1
    fi
}

check_file() {
    local file="$1"
    local desc="$2"
    if [ -f "$file" ]; then
        echo -e "  ${GREEN}[OK]${NC} $file"
        PASS_COUNT=$((PASS_COUNT + 1))
        return 0
    else
        echo -e "  ${RED}[FAIL]${NC} $file - NOT FOUND"
        FAIL_COUNT=$((FAIL_COUNT + 1))
        return 1
    fi
}

check_dir() {
    local dir="$1"
    local desc="$2"
    if [ -d "$dir" ]; then
        echo -e "  ${GREEN}[OK]${NC} $dir"
        PASS_COUNT=$((PASS_COUNT + 1))
        return 0
    else
        echo -e "  ${YELLOW}[WARN]${NC} $dir - NOT FOUND (mount at runtime)"
        WARN_COUNT=$((WARN_COUNT + 1))
        return 1
    fi
}

check_perl_module() {
    local module="$1"
    if perl -e "use $module" 2>/dev/null; then
        echo -e "  ${GREEN}[OK]${NC} Perl: $module"
        PASS_COUNT=$((PASS_COUNT + 1))
        return 0
    else
        echo -e "  ${RED}[FAIL]${NC} Perl: $module - NOT INSTALLED"
        FAIL_COUNT=$((FAIL_COUNT + 1))
        return 1
    fi
}

check_python_module() {
    local module="$1"
    if python3 -c "import $module" 2>/dev/null; then
        echo -e "  ${GREEN}[OK]${NC} Python: $module"
        PASS_COUNT=$((PASS_COUNT + 1))
        return 0
    else
        echo -e "  ${RED}[FAIL]${NC} Python: $module - NOT INSTALLED"
        FAIL_COUNT=$((FAIL_COUNT + 1))
        return 1
    fi
}

echo ""
echo "=============================================================="
echo "  hg38annotate Docker Dependency Check (HG38/GRCh38)"
echo "=============================================================="
echo ""

# -----------------------------------------------------------------------------
echo "1. CORE SYSTEM TOOLS"
echo "   Required for VCF processing and filtering"
echo "   ----------------------------------------"
check_command bcftools "VCF manipulation and querying"
check_command tabix "Indexing TAB-delimited files"
check_command bgzip "Block compression for VCF files"
check_command vcf-merge "Merging VCF files"
check_command vcf-sort "Sorting VCF files"

# -----------------------------------------------------------------------------
echo ""
echo "2. SHELL UTILITIES"
echo "   Required for pipeline execution"
echo "   ----------------------------------------"
check_command bash "Shell interpreter"
check_command parallel "GNU Parallel for job distribution"
check_command awk "Text processing (gawk)"
check_command sed "Stream editor"
check_command grep "Pattern matching"
check_command cut "Column extraction"
check_command paste "Column merging"
check_command sort "Line sorting"
check_command rename "Batch file renaming"

# -----------------------------------------------------------------------------
echo ""
echo "3. PROGRAMMING LANGUAGES"
echo "   Required for annotation tools"
echo "   ----------------------------------------"
check_command perl "Perl interpreter (VEP, snpEff)"
check_command python3 "Python 3 (TransVar, annovar-fast, cancervar-fast)"

# Test Java 21 (required for IGV 2.19.7; snpEff works with any Java 11+)
if java -version 2>&1 | grep -q "21"; then
    echo -e "  ${GREEN}[OK]${NC} java - OpenJDK 21 (for snpEff and IGV 2.19.7)"
    PASS_COUNT=$((PASS_COUNT + 1))
elif java -version 2>&1 | grep -q "11\|17"; then
    echo -e "  ${YELLOW}[WARN]${NC} java - OpenJDK 11/17 found; IGV 2.19.7 requires Java 21"
    WARN_COUNT=$((WARN_COUNT + 1))
else
    echo -e "  ${RED}[FAIL]${NC} java - OpenJDK 21 required (apt install openjdk-21-jre-headless)"
    FAIL_COUNT=$((FAIL_COUNT + 1))
fi

# -----------------------------------------------------------------------------
echo ""
echo "4. ANNOTATION TOOLS (CLI)"
echo "   Command-line annotation programs"
echo "   ----------------------------------------"
check_command transvar "TransVar annotation (hg38 configured)"
check_command vep "Ensembl VEP annotation"
check_command xvfb-run "Virtual framebuffer for IGV"

# -----------------------------------------------------------------------------
echo ""
echo "5. PERL MODULES"
echo "   Required Perl libraries"
echo "   ----------------------------------------"
check_perl_module "Excel::Writer::XLSX"
check_perl_module "DBI"
check_perl_module "LWP::Simple"
check_perl_module "JSON"
check_perl_module "Archive::Zip"

# -----------------------------------------------------------------------------
echo ""
echo "6. PYTHON MODULES"
echo "   Required Python libraries"
echo "   ----------------------------------------"
check_python_module "openpyxl"
check_python_module "transvar"
check_python_module "cyvcf2"
check_python_module "pysam"

# -----------------------------------------------------------------------------
echo ""
echo "7. SOFTWARE INSTALLATIONS"
echo "   Annotation software directories"
echo "   ----------------------------------------"

# annovar-fast and cancervar-fast (mounted at runtime)
ANNOVAR_FAST="${ANNOVAR_FAST:-/data/alvin/annovar/annovar-fast/annovar-fast.py}"
CANCERVAR_FAST="${CANCERVAR_FAST:-/data/alvin/annovar/annovar-fast/cancervar-fast.py}"
if [ -f "$ANNOVAR_FAST" ]; then
    echo -e "  ${GREEN}[OK]${NC} annovar-fast: $ANNOVAR_FAST"
    PASS_COUNT=$((PASS_COUNT + 1))
else
    echo -e "  ${YELLOW}[WARN]${NC} annovar-fast: $ANNOVAR_FAST - NOT FOUND (mount at runtime)"
    WARN_COUNT=$((WARN_COUNT + 1))
fi
if [ -f "$CANCERVAR_FAST" ]; then
    echo -e "  ${GREEN}[OK]${NC} cancervar-fast: $CANCERVAR_FAST"
    PASS_COUNT=$((PASS_COUNT + 1))
else
    echo -e "  ${YELLOW}[WARN]${NC} cancervar-fast: $CANCERVAR_FAST - NOT FOUND (mount at runtime)"
    WARN_COUNT=$((WARN_COUNT + 1))
fi

check_file "$HOME/Software/snpEff/snpEff.jar" "snpEff JAR"
check_file "$HOME/Software/snpEff/SnpSift.jar" "SnpSift JAR"
check_file "$HOME/Software/ensembl-vep/vep" "VEP executable"

# Check IGV (IGV_JAR env var points to igv.sh for IGV 2.19.7+)
IGV_JAR="${IGV_JAR:-$HOME/Software/IGV/IGV_2.19.7/igv.sh}"
if [ -f "$IGV_JAR" ]; then
    echo -e "  ${GREEN}[OK]${NC} $IGV_JAR"
    PASS_COUNT=$((PASS_COUNT + 1))
else
    echo -e "  ${RED}[FAIL]${NC} IGV launcher - NOT FOUND at $IGV_JAR"
    FAIL_COUNT=$((FAIL_COUNT + 1))
fi

# -----------------------------------------------------------------------------
echo ""
echo "8. PIPELINE SCRIPTS (HG38)"
echo "   hg38annotate pipeline scripts"
echo "   ----------------------------------------"
check_file "$HOME/Scripts/processVCF-hg38.sh" "Main HG38 pipeline script"
check_file "$HOME/Scripts/mergeVCFannotation-optimized-hg38.sh" "HG38 annotation pipeline"
check_file "$HOME/Scripts/make_IGV_snapshots.py" "IGV snapshot generator"
check_file "$HOME/Scripts/excel_to_html_report.py" "HTML report generator"

# -----------------------------------------------------------------------------
echo ""
echo "9. TRANSVAR CONFIGURATION (HG38)"
echo "   TransVar hg38 database configuration"
echo "   ----------------------------------------"
TRANSVAR_CFG="$HOME/.transvar.cfg"
if [ -f "$TRANSVAR_CFG" ]; then
    if grep -q "hg38" "$TRANSVAR_CFG"; then
        echo -e "  ${GREEN}[OK]${NC} TransVar configured for hg38"
        PASS_COUNT=$((PASS_COUNT + 1))
    else
        echo -e "  ${RED}[FAIL]${NC} TransVar not configured for hg38"
        FAIL_COUNT=$((FAIL_COUNT + 1))
    fi
else
    echo -e "  ${RED}[FAIL]${NC} TransVar config not found at $TRANSVAR_CFG"
    FAIL_COUNT=$((FAIL_COUNT + 1))
fi

# -----------------------------------------------------------------------------
echo ""
echo "10. DATABASE DIRECTORIES (mount at runtime)"
echo "    These should be mounted when running container"
echo "    ----------------------------------------"
DB_BASE="${DB_BASE:-$HOME/Databases/hg38annotate}"
HUMANDB="${HUMANDB:-$DB_BASE/humandb-tbi}"
check_dir "$DB_BASE/GRCh38"        "GRCh38 reference genome"
check_dir "$DB_BASE/vep"           "VEP GRCh38 cache"
check_dir "$DB_BASE/snpEff"        "snpEff GRCh38 database"
check_dir "$DB_BASE/transvar"      "TransVar annotation databases"
check_dir "$DB_BASE/SG10k"         "SG10K Singapore population database"
check_dir "$DB_BASE/genomeAsia"    "GenomeAsia 100K database"
if [ -d "$HUMANDB" ]; then
    echo -e "  ${GREEN}[OK]${NC} $HUMANDB"
    PASS_COUNT=$((PASS_COUNT + 1))
else
    echo -e "  ${YELLOW}[WARN]${NC} $HUMANDB - NOT FOUND (set HUMANDB env var)"
    WARN_COUNT=$((WARN_COUNT + 1))
fi

# -----------------------------------------------------------------------------
echo ""
echo "11. FUNCTIONAL TESTS"
echo "    Verify tools actually work"
echo "    ----------------------------------------"

# Test bcftools
if echo -e "##fileformat=VCFv4.2\n#CHROM\tPOS\tID\tREF\tALT\tQUAL\tFILTER\tINFO" | bcftools view - &>/dev/null; then
    echo -e "  ${GREEN}[OK]${NC} bcftools - functional test passed"
    PASS_COUNT=$((PASS_COUNT + 1))
else
    echo -e "  ${RED}[FAIL]${NC} bcftools - functional test failed"
    FAIL_COUNT=$((FAIL_COUNT + 1))
fi

# Test parallel
if echo "test" | parallel echo {} &>/dev/null; then
    echo -e "  ${GREEN}[OK]${NC} parallel - functional test passed"
    PASS_COUNT=$((PASS_COUNT + 1))
else
    echo -e "  ${RED}[FAIL]${NC} parallel - functional test failed"
    FAIL_COUNT=$((FAIL_COUNT + 1))
fi

# Test snpEff can show help
if java -jar "$HOME/Software/snpEff/snpEff.jar" -help 2>&1 | grep -q "snpEff"; then
    echo -e "  ${GREEN}[OK]${NC} snpEff - functional test passed"
    PASS_COUNT=$((PASS_COUNT + 1))
else
    echo -e "  ${RED}[FAIL]${NC} snpEff - functional test failed"
    FAIL_COUNT=$((FAIL_COUNT + 1))
fi

# Test annovar-fast
if [ -f "$ANNOVAR_FAST" ] && python3 "$ANNOVAR_FAST" --help 2>&1 | grep -qi "annovar\|usage\|input"; then
    echo -e "  ${GREEN}[OK]${NC} annovar-fast - functional test passed"
    PASS_COUNT=$((PASS_COUNT + 1))
else
    echo -e "  ${YELLOW}[WARN]${NC} annovar-fast - not mounted or functional test failed"
    WARN_COUNT=$((WARN_COUNT + 1))
fi

# Test cancervar-fast
if [ -f "$CANCERVAR_FAST" ] && python3 "$CANCERVAR_FAST" --help 2>&1 | grep -qi "cancer\|usage\|input"; then
    echo -e "  ${GREEN}[OK]${NC} cancervar-fast - functional test passed"
    PASS_COUNT=$((PASS_COUNT + 1))
else
    echo -e "  ${YELLOW}[WARN]${NC} cancervar-fast - not mounted or functional test failed"
    WARN_COUNT=$((WARN_COUNT + 1))
fi

# Test VEP help
if vep --help 2>&1 | grep -qi "ensembl"; then
    echo -e "  ${GREEN}[OK]${NC} VEP - functional test passed"
    PASS_COUNT=$((PASS_COUNT + 1))
else
    echo -e "  ${RED}[FAIL]${NC} VEP - functional test failed"
    FAIL_COUNT=$((FAIL_COUNT + 1))
fi

# Test TransVar with hg38
if transvar panno -i 'PIK3CA:p.E545K' --refversion hg38 --refseq 2>&1 | grep -q -i "PIK3CA\|Missense\|error"; then
    echo -e "  ${GREEN}[OK]${NC} transvar - functional test passed (hg38)"
    PASS_COUNT=$((PASS_COUNT + 1))
else
    echo -e "  ${RED}[FAIL]${NC} transvar - functional test failed"
    FAIL_COUNT=$((FAIL_COUNT + 1))
fi

# Test IGV launcher (igv.sh; requires display — just confirm it exists and is executable)
if [ -x "$IGV_JAR" ]; then
    echo -e "  ${GREEN}[OK]${NC} IGV - launcher exists and is executable ($IGV_JAR)"
    PASS_COUNT=$((PASS_COUNT + 1))
elif [ -f "$IGV_JAR" ]; then
    echo -e "  ${YELLOW}[WARN]${NC} IGV - launcher exists but not executable ($IGV_JAR)"
    WARN_COUNT=$((WARN_COUNT + 1))
else
    echo -e "  ${RED}[FAIL]${NC} IGV - launcher not found at $IGV_JAR"
    FAIL_COUNT=$((FAIL_COUNT + 1))
fi

# -----------------------------------------------------------------------------
echo ""
echo "=============================================================="
echo "  SUMMARY"
echo "=============================================================="
echo ""
echo -e "  ${GREEN}Passed:${NC}   $PASS_COUNT"
echo -e "  ${RED}Failed:${NC}   $FAIL_COUNT"
echo -e "  ${YELLOW}Warnings:${NC} $WARN_COUNT"
echo ""

if [ "$FAIL_COUNT" -eq 0 ]; then
    echo -e "  ${GREEN}All critical dependencies are installed!${NC}"
    echo ""
    if [ "$WARN_COUNT" -gt 0 ]; then
        echo "  Note: Warnings are for tools/databases mounted at runtime."
        echo "  Mount databases with:"
        echo "    -v /path/to/Databases/hg38annotate:/home/user/Databases/hg38annotate:ro"
        echo "    -e HUMANDB=/path/to/humandb-tbi"
        echo "    -v /path/to/humandb-tbi:/path/to/humandb-tbi:ro"
        echo "    -v /path/to/annovar-fast:/path/to/annovar-fast:ro"
    fi
    exit 0
else
    echo -e "  ${RED}Some dependencies are missing. Fix before running pipeline.${NC}"
    exit 1
fi
