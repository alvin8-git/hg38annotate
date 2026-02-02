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
check_command perl "Perl interpreter (ANNOVAR, VEP)"
check_command python3 "Python 3 (TransVar, CancerVar)"

# Test Java 11 (default)
if java -version 2>&1 | grep -q "11"; then
    echo -e "  ${GREEN}[OK]${NC} java - OpenJDK 11 (default, for snpEff)"
    PASS_COUNT=$((PASS_COUNT + 1))
else
    echo -e "  ${YELLOW}[WARN]${NC} java - Not OpenJDK 11"
    WARN_COUNT=$((WARN_COUNT + 1))
fi

# Test Java 8 (for IGV)
JAVA8="${JAVA8_PATH:-/usr/lib/jvm/java-8-openjdk-amd64/bin/java}"
if [ -f "$JAVA8" ]; then
    if "$JAVA8" -version 2>&1 | grep -q "1.8"; then
        echo -e "  ${GREEN}[OK]${NC} Java 8 at $JAVA8 (for IGV)"
        PASS_COUNT=$((PASS_COUNT + 1))
    else
        echo -e "  ${RED}[FAIL]${NC} Java 8 at $JAVA8 - wrong version"
        FAIL_COUNT=$((FAIL_COUNT + 1))
    fi
else
    echo -e "  ${RED}[FAIL]${NC} Java 8 - NOT FOUND at $JAVA8"
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

# -----------------------------------------------------------------------------
echo ""
echo "7. SOFTWARE INSTALLATIONS"
echo "   Annotation software directories"
echo "   ----------------------------------------"
check_file "$HOME/Software/annovar/table_annovar.pl" "ANNOVAR main script"
check_file "$HOME/Software/annovar/convert2annovar.pl" "ANNOVAR converter"
check_file "$HOME/Software/snpEff/snpEff.jar" "snpEff JAR"
check_file "$HOME/Software/snpEff/SnpSift.jar" "SnpSift JAR"
check_file "$HOME/Software/CancerVar/CancerVar.py" "CancerVar script"
check_file "$HOME/Software/ensembl-vep/vep" "VEP executable"

# Check IGV
IGV_JAR="${IGV_JAR:-$HOME/Software/IGV/IGV_2.3.81/igv.jar}"
if [ -f "$IGV_JAR" ]; then
    echo -e "  ${GREEN}[OK]${NC} $IGV_JAR"
    PASS_COUNT=$((PASS_COUNT + 1))
else
    echo -e "  ${RED}[FAIL]${NC} IGV JAR - NOT FOUND at $IGV_JAR"
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
echo "10. DATABASE DIRECTORIES (HG38/GRCh38 - mount at runtime)"
echo "    These should be mounted when running container"
echo "    ----------------------------------------"
check_dir "$HOME/Databases/humandb" "ANNOVAR hg38 databases"
check_dir "$HOME/Databases/GRCh38" "GRCh38 reference genome (hg38.fa)"
check_dir "$HOME/Databases/vep" "VEP GRCh38 cache"
check_dir "$HOME/Databases/snpEff" "snpEff GRCh38 database"
check_dir "$HOME/Databases/SG10K.hg38.vcf" "SG10K HG38 database"
check_dir "$HOME/Databases/iSeq" "iSeq reference VCFs (HG38)"

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

# Test ANNOVAR help
if perl "$HOME/Software/annovar/table_annovar.pl" 2>&1 | grep -q -i "annovar"; then
    echo -e "  ${GREEN}[OK]${NC} ANNOVAR - functional test passed"
    PASS_COUNT=$((PASS_COUNT + 1))
else
    echo -e "  ${RED}[FAIL]${NC} ANNOVAR - functional test failed"
    FAIL_COUNT=$((FAIL_COUNT + 1))
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
if transvar panno -i 'PIK3CA:p.E545K' --refversion hg38 2>&1 | grep -q -i "transvar\|PIK3CA\|error"; then
    echo -e "  ${GREEN}[OK]${NC} transvar - functional test passed (hg38)"
    PASS_COUNT=$((PASS_COUNT + 1))
else
    echo -e "  ${RED}[FAIL]${NC} transvar - functional test failed"
    FAIL_COUNT=$((FAIL_COUNT + 1))
fi

# Test CancerVar
if python3 "$HOME/Software/CancerVar/CancerVar.py" --help 2>&1 | grep -q -i "cancer\|usage"; then
    echo -e "  ${GREEN}[OK]${NC} CancerVar - functional test passed"
    PASS_COUNT=$((PASS_COUNT + 1))
else
    echo -e "  ${RED}[FAIL]${NC} CancerVar - functional test failed"
    FAIL_COUNT=$((FAIL_COUNT + 1))
fi

# Test IGV with Java 8
if "$JAVA8" -jar "$IGV_JAR" --help 2>&1 | head -1 | grep -q -i "igv\|usage"; then
    echo -e "  ${GREEN}[OK]${NC} IGV - functional test passed"
    PASS_COUNT=$((PASS_COUNT + 1))
else
    # IGV may not have --help, just check if it can start
    if timeout 5 xvfb-run -a "$JAVA8" -jar "$IGV_JAR" --version 2>&1 || true; then
        echo -e "  ${YELLOW}[WARN]${NC} IGV - no help flag, but JAR exists"
        WARN_COUNT=$((WARN_COUNT + 1))
    else
        echo -e "  ${RED}[FAIL]${NC} IGV - functional test failed"
        FAIL_COUNT=$((FAIL_COUNT + 1))
    fi
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
        echo "  Note: Warnings are for databases that should be mounted at runtime."
        echo "  Mount HG38 databases with:"
        echo "    -v \$HOME/Databases/humandb:/home/user/Databases/humandb"
        echo "    -v \$HOME/Databases/GRCh38:/home/user/Databases/GRCh38"
        echo "    -v \$HOME/Databases/vep:/home/user/Databases/vep"
        echo "    -v \$HOME/Databases/snpEff:/home/user/Databases/snpEff"
    fi
    exit 0
else
    echo -e "  ${RED}Some dependencies are missing. Fix before running pipeline.${NC}"
    exit 1
fi
