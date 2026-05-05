#!/usr/bin/env bash
# lab_collect.sh SERVER CONTAINER_NAME OUTPUT_DIR
#
# Collect logs from a finished worker container into OUTPUT_DIR (path inside the
# shared workspace). The worker's results files are expected to already be
# written to the mounted workspace by the worker itself; this script only
# captures stdout/stderr and metadata that don't naturally land in the workspace.

set -euo pipefail

SERVER="${1:?usage: lab_collect.sh SERVER CONTAINER OUTPUT_DIR}"
NAME="${2:?usage: lab_collect.sh SERVER CONTAINER OUTPUT_DIR}"
OUT="${3:?usage: lab_collect.sh SERVER CONTAINER OUTPUT_DIR}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lab.env"

_KEY="${SERVER//-/_}"
HOST_VAR="LAB_${_KEY}_HOST"
HOST="${!HOST_VAR:-}"
[[ -z "$HOST" ]] && { echo "ERROR: unknown server $SERVER" >&2; exit 2; }

mkdir -p "$OUT"

ssh -o BatchMode=yes "$HOST" "docker logs $NAME"        > "$OUT/stdout_stderr.log"  2>"$OUT/.collect_err.log" || true
ssh -o BatchMode=yes "$HOST" "docker inspect $NAME"     > "$OUT/inspect.json" 2>>"$OUT/.collect_err.log"     || true

cat > "$OUT/_meta.txt" <<EOF
container_name=$NAME
server=$SERVER
collected_at=$(date -Is)
EOF

echo "Collected $NAME → $OUT"
