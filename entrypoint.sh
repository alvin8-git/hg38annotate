#!/bin/bash
# =============================================================================
# entrypoint.sh - Docker entrypoint for hg38annotate container
# =============================================================================
# Handles two Docker modes:
#
# Rootless Docker (container uid 0 = host unprivileged user):
#   Stay as root — files written by the container are owned by the host user
#   automatically, with no chown required.
#
# Regular Docker (container uid 0 = real root):
#   Remap container 'user' UID/GID to match the host user (via HOST_UID /
#   HOST_GID env vars), then drop privileges via gosu.
#   Pass host UID/GID at runtime:
#     docker run -e HOST_UID=$(id -u) -e HOST_GID=$(id -g) ...
# =============================================================================

set -e

TARGET_USER="user"

# =============================================================================
# Generate TransVar config based on DB_BASE (may be overridden by -e DB_BASE=…)
# This must run before the privilege drop so we can write to /home/user.
# =============================================================================
_db="${DB_BASE:-/home/user/Databases/hg38annotate}"
_tvar="$_db/transvar"
cat > /home/$TARGET_USER/.transvar.cfg << EOF
[DEFAULT]
refversion = hg38

[hg38]
reference = $_db/GRCh38/hg38.fa
refseq = $_tvar/hg38.refseq.gff.gz.transvardb
ccds = $_tvar/hg38.ccds.txt.transvardb
ensembl = $_tvar/hg38.ensembl.gtf.gz.transvardb
gencode = $_tvar/hg38.gencode.gtf.gz.transvardb
ucsc = $_tvar/hg38.ucsc.txt.gz.transvardb
EOF
chown $TARGET_USER:$TARGET_USER /home/$TARGET_USER/.transvar.cfg 2>/dev/null || true

if [ "$(id -u)" = "0" ]; then
    # Detect rootless Docker: in rootless mode, container uid 0 maps to the
    # host user's uid (non-zero). Check the first entry of uid_map.
    HOST_ROOT_UID=$(awk 'NR==1{print $2}' /proc/self/uid_map 2>/dev/null || echo "0")

    if [ "$HOST_ROOT_UID" != "0" ]; then
        # ---------------------------------------------------------------
        # Rootless Docker: container root = host user, no chown needed.
        # Files created as root here will be owned by the host user on disk.
        # ---------------------------------------------------------------
        mkdir -p /data/output /data/vcf/annotation 2>/dev/null || true
        exec "$@"
    else
        # ---------------------------------------------------------------
        # Regular Docker: remap 'user' to the host UID/GID, drop privileges.
        # ---------------------------------------------------------------
        HOST_UID="${HOST_UID:-1000}"
        HOST_GID="${HOST_GID:-$HOST_UID}"

        CURRENT_UID=$(id -u "$TARGET_USER")
        CURRENT_GID=$(id -g "$TARGET_USER")

        if [ "$HOST_GID" != "$CURRENT_GID" ]; then
            groupmod -g "$HOST_GID" "$TARGET_USER" 2>/dev/null || true
        fi
        if [ "$HOST_UID" != "$CURRENT_UID" ]; then
            usermod -u "$HOST_UID" "$TARGET_USER" 2>/dev/null || true
            chown -R "$TARGET_USER":"$TARGET_USER" /home/"$TARGET_USER" 2>/dev/null || true
        fi

        mkdir -p /data/output /data/vcf/annotation 2>/dev/null || true
        chown "$TARGET_USER":"$TARGET_USER" /data/output /data/vcf/annotation 2>/dev/null || true

        exec gosu "$TARGET_USER" "$@"
    fi
fi

# Already running as non-root
exec "$@"
