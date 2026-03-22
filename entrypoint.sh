#!/bin/sh
set -e

QUAKE3_DIR="/opt/quake3"
BASEQ3_DIR="${QUAKE3_DIR}/baseq3"
SERVER_BIN="${QUAKE3_DIR}/bin/ioq3ded"

# Fallback: check alternative binary locations from cmake install
if [ ! -f "${SERVER_BIN}" ]; then
    for candidate in \
        "${QUAKE3_DIR}/ioq3ded" \
        "${QUAKE3_DIR}/ioq3ded.x86_64" \
        "${QUAKE3_DIR}/bin/ioq3ded.x86_64"; do
        if [ -f "${candidate}" ]; then
            SERVER_BIN="${candidate}"
            break
        fi
    done
fi

if [ ! -x "${SERVER_BIN}" ]; then
    echo "ERROR: ioq3ded binary not found. Searched in ${QUAKE3_DIR}/{bin/,}ioq3ded{,.x86_64}"
    exit 1
fi

# Check for game data
if [ ! -f "${BASEQ3_DIR}/pak0.pk3" ]; then
    echo "============================================================"
    echo "WARNING: pak0.pk3 not found in ${BASEQ3_DIR}/"
    echo ""
    echo "You must mount your Quake 3 Arena game data:"
    echo "  docker run -v /path/to/baseq3:/opt/quake3/baseq3 ..."
    echo ""
    echo "The baseq3 directory must contain at least pak0.pk3"
    echo "from a legal copy of Quake 3 Arena."
    echo "============================================================"
    exit 1
fi

# Validate environment inputs — only allow safe characters
validate_input() {
    case "$1" in
        *[!a-zA-Z0-9._-]*) echo "ERROR: Invalid characters in $2: $1"; exit 1 ;;
    esac
}

# Server configuration
Q3_PORT="${Q3_PORT:-27960}"
Q3_MAP="${Q3_MAP:-q3dm17}"
Q3_CONFIG="${Q3_CONFIG:-server.cfg}"

validate_input "${Q3_PORT}" "Q3_PORT"
validate_input "${Q3_MAP}" "Q3_MAP"
validate_input "${Q3_CONFIG}" "Q3_CONFIG"

# RCON password — injected via environment, never hardcoded
Q3_RCON="${Q3_RCON:-}"
if [ -n "${Q3_RCON}" ]; then
    validate_input "${Q3_RCON}" "Q3_RCON"
fi

echo "Starting Quake 3 Arena dedicated server..."
echo "  Port:   ${Q3_PORT}"
echo "  Map:    ${Q3_MAP}"
echo "  Config: ${Q3_CONFIG}"

RCON_ARGS=""
if [ -n "${Q3_RCON}" ]; then
    RCON_ARGS="+set rconpassword ${Q3_RCON}"
    echo "  RCON:   enabled"
else
    echo "  RCON:   disabled (no Q3_RCON set)"
fi

exec "${SERVER_BIN}" \
    +set fs_basepath "${QUAKE3_DIR}" \
    +set fs_homepath "${QUAKE3_DIR}/.q3a" \
    +set net_port "${Q3_PORT}" \
    +set dedicated 2 \
    +set com_hunkmegs 64 \
    ${RCON_ARGS} \
    +exec "${Q3_CONFIG}" \
    +map "${Q3_MAP}"
