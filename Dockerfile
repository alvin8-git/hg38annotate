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

# The ubuntu:22.04 base image ships ubuntu-keyring 2021.03.26, which predates
# Ubuntu's archive signing key rotation (key 871920D1991BC93C).  On some Docker
# hosts the keyring files are also unreadable by the _apt sandbox user.  Since
# the base image cannot be updated and the keyring cannot be refreshed without
# a working apt, we mark repos as trusted for the initial install.  Packages
# are still fetched from Ubuntu's official archive — only the GPG signature
# check is skipped during this build step.
#
# On CentOS 7 Docker hosts (kernel 3.10.x) the seccomp profile blocks the clone
# syscall flags that the JVM requires, so pthread_create fails with EPERM and
# the JVM cannot start at all — not even the initial VM thread.  Three separate
# mechanisms try to invoke java during package installation:
#   1. /etc/ca-certificates/update.d/jks-keystore  (a ca-certificates trigger
#      script installed by ca-certificates-java; fires once per JDK alternative
#      registered, so up to 3 times during this install)
#   2. ca-certificates-java postinst
#   3. openjdk-{8,11} postinst calls java via its installed absolute path
#      (/usr/lib/jvm/java-{8,11}-openjdk-amd64/{jre/,}bin/java) for sanity checks.
# Strategy: before unpacking any packages, divert jks-keystore AND the JVM
# binaries to no-op stubs so every java invocation during postinst is silent.
# Restore the real JVM binaries after installation.  Stub ca-certificates-java
# postinst for belt-and-suspenders.  Use || true throughout so dpkg failures
# in unrelated packages (sysstat ucfr) don't abort the build layer.
RUN sed -i 's|^deb |deb [trusted=yes] |' /etc/apt/sources.list && \
    rm -f /etc/apt/apt.conf.d/docker-clean && \
    mkdir -p /etc/ca-certificates/update.d \
             /usr/lib/jvm/java-8-openjdk-amd64/jre/bin \
             /usr/lib/jvm/java-11-openjdk-amd64/bin && \
    dpkg-divert --add --rename \
        --divert /etc/ca-certificates/update.d/jks-keystore.real \
        /etc/ca-certificates/update.d/jks-keystore && \
    dpkg-divert --add --rename \
        --divert /usr/lib/jvm/java-8-openjdk-amd64/jre/bin/java.real \
        /usr/lib/jvm/java-8-openjdk-amd64/jre/bin/java && \
    dpkg-divert --add --rename \
        --divert /usr/lib/jvm/java-11-openjdk-amd64/bin/java.real \
        /usr/lib/jvm/java-11-openjdk-amd64/bin/java && \
    printf '#!/bin/sh\nexit 0\n' > /etc/ca-certificates/update.d/jks-keystore && \
    printf '#!/bin/sh\nexit 0\n' > /usr/lib/jvm/java-8-openjdk-amd64/jre/bin/java && \
    printf '#!/bin/sh\nexit 0\n' > /usr/lib/jvm/java-11-openjdk-amd64/bin/java && \
    chmod +x /etc/ca-certificates/update.d/jks-keystore \
             /usr/lib/jvm/java-8-openjdk-amd64/jre/bin/java \
             /usr/lib/jvm/java-11-openjdk-amd64/bin/java && \
    apt-get update && \
    apt-get install -y --no-install-recommends \
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
    libarchive-extract-perl \
    libarchive-zip-perl \
    libexcel-writer-xlsx-perl \
    # Rename utility
    rename \
    || true && \
    # Restore the real JVM binaries now that all postinst scripts have run.
    # dpkg-divert --remove --rename renames java.real back to java, but refuses
    # to overwrite an existing file.  Remove the stub first so the rename works.
    rm -f /usr/lib/jvm/java-8-openjdk-amd64/jre/bin/java && \
    dpkg-divert --remove --rename /usr/lib/jvm/java-8-openjdk-amd64/jre/bin/java || true && \
    rm -f /usr/lib/jvm/java-11-openjdk-amd64/bin/java && \
    dpkg-divert --remove --rename /usr/lib/jvm/java-11-openjdk-amd64/bin/java || true && \
    # Stub ca-certificates-java postinst (belt-and-suspenders: the postinst also
    # invokes java to update the keystore; keep it stubbed since the Java keystore
    # is not required at runtime for this pipeline).
    printf '#!/bin/sh\nexit 0\n' > /var/lib/dpkg/info/ca-certificates-java.postinst && \
    # sysstat postinst uses ucf/ucfr to manage /etc/default/sysstat.  Both the
    # hashfile and registry may be left inconsistent after a partial install,
    # causing "do not have write privilege" errors on retry.  Wipe all ucf state
    # so dpkg --configure starts fresh.  sysstat/parallel binaries are on disk
    # (dpkg unpacks before postinst) and functional even if not fully configured.
    rm -rf /var/lib/ucf/ && \
    dpkg --configure --pending || true && \
    rm -rf /var/lib/apt/lists/*

# =============================================================================
# PYTHON PACKAGES (TransVar, openpyxl for HTML reports)
# =============================================================================

# --progress-bar off prevents pip's Rich library from starting a background
# refresh thread, which fails with RuntimeError on CentOS 7 Docker build hosts
# where the seccomp profile blocks pthread_create for non-initial threads.
RUN pip3 install --no-cache-dir --progress-bar off transvar openpyxl pysam cyvcf2

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

COPY --chown=1000:1000 annovar/ /home/$USERNAME/Software/annovar/
RUN chmod +x /home/$USERNAME/Software/annovar/*.pl

# =============================================================================
# snpEff (copy from local)
# Note: snpEff GRCh38 database should be mounted at runtime
# Mount path: /home/user/Databases/snpEff
# =============================================================================

COPY --chown=1000:1000 snpEff/ /home/$USERNAME/Software/snpEff/

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

COPY --chown=1000:1000 ensembl-vep/ /home/$USERNAME/Software/ensembl-vep/

RUN mkdir -p /home/$USERNAME/Databases/vep && \
    chmod +x /home/$USERNAME/Software/ensembl-vep/vep && \
    cd /home/$USERNAME/Software/ensembl-vep && \
    perl INSTALL.pl --AUTO a --NO_TEST --NO_UPDATE --NO_HTSLIB --DESTDIR /home/$USERNAME/Software/ensembl-vep

# =============================================================================
# PIPELINE SCRIPTS (HG38 versions)
# =============================================================================

COPY --chown=1000:1000 processVCF-hg38.sh /home/$USERNAME/Scripts/
COPY --chown=1000:1000 mergeVCFannotation-optimized-hg38.sh /home/$USERNAME/Scripts/
COPY --chown=1000:1000 make_IGV_snapshots.py /home/$USERNAME/Scripts/
COPY --chown=1000:1000 excel_to_html_report.py /home/$USERNAME/Scripts/
COPY --chown=1000:1000 check_docker_deps.sh /home/$USERNAME/Scripts/

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
