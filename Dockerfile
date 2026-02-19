# =============================================================================
# Dockerfile for hg38annotate Pipeline
# =============================================================================
# Ubuntu-based container with annotation tools for HG38/GRCh38 reference
#
# Build: docker build -t hg38annotate .
# Run:   docker run -v /path/to/Databases:/home/user/Databases \
#                   -v /path/to/data:/data \
#                   hg38annotate
# =============================================================================

FROM ubuntu:22.04

LABEL maintainer="Alvin Ng"
LABEL description="VCF Annotation Pipeline for HG38/GRCh38 Reference Genome"
LABEL version="1.0"

# Prevent interactive prompts during package installation
ENV DEBIAN_FRONTEND=noninteractive
ENV TZ=UTC

# Create non-root user
ARG USERNAME=user
ARG USER_UID=1000
ARG USER_GID=$USER_UID

RUN groupadd --gid $USER_GID $USERNAME \
    && useradd --uid $USER_UID --gid $USER_GID -m $USERNAME

# =============================================================================
# SYSTEM PACKAGES
# =============================================================================

RUN apt-get update && apt-get install -y --no-install-recommends \
    # Core utilities
    bash \
    coreutils \
    gawk \
    sed \
    grep \
    curl \
    wget \
    git \
    ca-certificates \
    # Bioinformatics tools
    bcftools \
    tabix \
    vcftools \
    # Programming languages
    perl \
    python3 \
    python3-pip \
    openjdk-11-jre-headless \
    openjdk-8-jre-headless \
    # IGV dependencies (headless display)
    xvfb \
    libxrender1 \
    libxtst6 \
    libxi6 \
    # Parallel processing
    parallel \
    # Compression
    gzip \
    bzip2 \
    xz-utils \
    unzip \
    # User switching for entrypoint
    gosu \
    # Required for Perl modules and compilation
    build-essential \
    cpanminus \
    zlib1g-dev \
    python3-dev \
    libbz2-dev \
    liblzma-dev \
    # Required for VEP
    libdbi-perl \
    libdbd-mysql-perl \
    libwww-perl \
    libjson-perl \
    libarchive-zip-perl \
    # Rename utility
    rename \
    && rm -rf /var/lib/apt/lists/*

# =============================================================================
# PERL MODULES
# =============================================================================

RUN cpanm --notest Excel::Writer::XLSX

# =============================================================================
# PYTHON PACKAGES (TransVar, openpyxl for HTML reports)
# =============================================================================

RUN pip3 install --no-cache-dir transvar openpyxl pysam cyvcf2

# Configure TransVar with hg38 reference
# Download annotation databases and create config pointing to mounted reference genome
RUN transvar config --download_anno --refversion hg38 --skip_reference && \
    TRANSVAR_DB=/usr/local/lib/python3.10/dist-packages/transvar/transvar.download && \
    echo "[DEFAULT]" > /home/$USERNAME/.transvar.cfg && \
    echo "refversion = hg38" >> /home/$USERNAME/.transvar.cfg && \
    echo "" >> /home/$USERNAME/.transvar.cfg && \
    echo "[hg38]" >> /home/$USERNAME/.transvar.cfg && \
    echo "reference = /home/$USERNAME/Databases/GRCh38/hg38.fa" >> /home/$USERNAME/.transvar.cfg && \
    echo "refseq = $TRANSVAR_DB/hg38.refseq.gff.gz.transvardb" >> /home/$USERNAME/.transvar.cfg && \
    echo "ccds = $TRANSVAR_DB/hg38.ccds.txt.transvardb" >> /home/$USERNAME/.transvar.cfg && \
    echo "ensembl = $TRANSVAR_DB/hg38.ensembl.gtf.gz.transvardb" >> /home/$USERNAME/.transvar.cfg && \
    echo "gencode = $TRANSVAR_DB/hg38.gencode.gtf.gz.transvardb" >> /home/$USERNAME/.transvar.cfg && \
    echo "ucsc = $TRANSVAR_DB/hg38.ucsc.txt.gz.transvardb" >> /home/$USERNAME/.transvar.cfg && \
    echo "aceview = $TRANSVAR_DB/hg38.aceview.gff.gz.transvardb" >> /home/$USERNAME/.transvar.cfg && \
    echo "known_gene = $TRANSVAR_DB/hg38.knowngene.gz.transvardb" >> /home/$USERNAME/.transvar.cfg && \
    chown $USERNAME:$USERNAME /home/$USERNAME/.transvar.cfg

# =============================================================================
# SOFTWARE DIRECTORY SETUP
# =============================================================================

RUN mkdir -p /home/$USERNAME/Software \
             /home/$USERNAME/Databases \
             /home/$USERNAME/Scripts

# =============================================================================
# ANNOVAR (copy from local)
# ANNOVAR requires registration - copy from local installation
# =============================================================================

COPY --chown=$USERNAME:$USERNAME annovar/ /home/$USERNAME/Software/annovar/
RUN chmod +x /home/$USERNAME/Software/annovar/*.pl

# =============================================================================
# snpEff (copy from local)
# Note: snpEff GRCh38 database should be mounted at runtime
# Mount path: /home/user/Databases/snpEff
# =============================================================================

COPY --chown=$USERNAME:$USERNAME snpEff/ /home/$USERNAME/Software/snpEff/

RUN chmod +x /home/$USERNAME/Software/snpEff/scripts/*.pl \
             /home/$USERNAME/Software/snpEff/scripts/*.sh 2>/dev/null || true && \
    mkdir -p /home/$USERNAME/Databases/snpEff && \
    ln -sf /home/$USERNAME/Databases/snpEff /home/$USERNAME/Software/snpEff/data

# =============================================================================
# IGV (Integrative Genomics Viewer) for snapshots
# IGV 2.3.81 requires Java 8
# =============================================================================

RUN mkdir -p /home/$USERNAME/Software/IGV && \
    cd /home/$USERNAME/Software/IGV && \
    wget -q https://data.broadinstitute.org/igv/projects/downloads/2.3/IGV_2.3.81.zip && \
    unzip -q IGV_2.3.81.zip && \
    rm IGV_2.3.81.zip && \
    chown -R $USERNAME:$USERNAME /home/$USERNAME/Software/IGV

ENV JAVA8_PATH=/usr/lib/jvm/java-8-openjdk-amd64/bin/java
ENV IGV_JAR=/home/$USERNAME/Software/IGV/IGV_2.3.81/igv.jar

# =============================================================================
# VEP (Ensembl Variant Effect Predictor)
# VEP software is included in the image
# VEP GRCh38 cache (28GB+) should be mounted at runtime: /home/user/Databases/vep
# =============================================================================

COPY --chown=$USERNAME:$USERNAME ensembl-vep/ /home/$USERNAME/Software/ensembl-vep/

RUN mkdir -p /home/$USERNAME/Databases/vep && \
    chmod +x /home/$USERNAME/Software/ensembl-vep/vep && \
    cd /home/$USERNAME/Software/ensembl-vep && \
    perl INSTALL.pl --AUTO a --NO_TEST --NO_UPDATE --DESTDIR /home/$USERNAME/Software/ensembl-vep

# =============================================================================
# PIPELINE SCRIPTS (HG38 versions)
# =============================================================================

COPY --chown=$USERNAME:$USERNAME processVCF-hg38.sh /home/$USERNAME/Scripts/
COPY --chown=$USERNAME:$USERNAME mergeVCFannotation-optimized-hg38.sh /home/$USERNAME/Scripts/
COPY --chown=$USERNAME:$USERNAME make_IGV_snapshots.py /home/$USERNAME/Scripts/
COPY --chown=$USERNAME:$USERNAME excel_to_html_report.py /home/$USERNAME/Scripts/
COPY --chown=$USERNAME:$USERNAME check_docker_deps.sh /home/$USERNAME/Scripts/

RUN chmod +x /home/$USERNAME/Scripts/*.sh /home/$USERNAME/Scripts/*.py

# =============================================================================
# ENVIRONMENT VARIABLES
# =============================================================================

ENV HOME=/home/$USERNAME
ENV PATH="/home/$USERNAME/Software/annovar:/home/$USERNAME/Software/snpEff:/home/$USERNAME/Software/ensembl-vep:/home/$USERNAME/Scripts:$PATH"
ENV PERL5LIB="/home/$USERNAME/Software/ensembl-vep/modules"
ENV ANNOVAR_FAST=/data/alvin/annovar/annovar-fast/annovar-fast.py
ENV CANCERVAR_FAST=/data/alvin/annovar/annovar-fast/cancervar-fast.py

# =============================================================================
# ENTRYPOINT SCRIPT
# =============================================================================

COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

# =============================================================================
# WORKING DIRECTORY AND ENTRYPOINT
# =============================================================================

WORKDIR /data

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["bash"]
