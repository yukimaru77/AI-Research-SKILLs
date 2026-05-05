#!/usr/bin/env bash
# lab_gpu_pick.sh SERVER [MIN_FREE_MIB]
#
# Pick a free GPU index on SERVER. "Free" means free memory >= MIN_FREE_MIB
# AND no other container is currently bound to that device by lab_dispatch.sh.
# Prints the chosen GPU index to stdout. Exits non-zero if no GPU qualifies.
#
# Used by autoresearch before lab_dispatch.sh.

set -euo pipefail

SERVER="${1:?usage: lab_gpu_pick.sh SERVER [MIN_FREE_MIB]}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lab.env"

THRESHOLD_DEFAULT="${GPU_BUSY_FREE_MIB_THRESHOLD:-2000}"
MIN_FREE_MIB="${2:-$THRESHOLD_DEFAULT}"

# Resolve LAB_<server>_HOST. Bash variable names cannot contain '-', so normalize.
_KEY="${SERVER//-/_}"
HOST_VAR="LAB_${_KEY}_HOST"
HOST="${!HOST_VAR:-}"
if [[ -z "$HOST" ]]; then
  echo "ERROR: unknown server '$SERVER'. Configure LAB_${_KEY}_HOST in lab.env." >&2
  exit 2
fi

# Per-device free memory (MiB) on the target server.
mapfile -t GPU_FREE < <(ssh -o BatchMode=yes "$HOST" \
  "nvidia-smi --query-gpu=index,memory.free --format=csv,noheader,nounits")

if [[ ${#GPU_FREE[@]} -eq 0 ]]; then
  echo "ERROR: nvidia-smi returned no GPUs on $HOST" >&2
  exit 3
fi

# GPU indices currently held by autoresearch-launched containers (label set by lab_dispatch.sh).
mapfile -t HELD < <(ssh -o BatchMode=yes "$HOST" \
  "docker ps --filter label=autoresearch.gpu --format '{{.Label \"autoresearch.gpu\"}}'" 2>/dev/null || true)

is_held() {
  local idx="$1"
  for h in "${HELD[@]}"; do
    [[ "$h" == "$idx" ]] && return 0
  done
  return 1
}

for line in "${GPU_FREE[@]}"; do
  idx="$(echo "$line" | awk -F',' '{gsub(/ /,"",$1); print $1}')"
  free="$(echo "$line" | awk -F',' '{gsub(/ /,"",$2); print $2}')"
  if (( free >= MIN_FREE_MIB )) && ! is_held "$idx"; then
    echo "$idx"
    exit 0
  fi
done

echo "ERROR: no free GPU on $SERVER (threshold=${MIN_FREE_MIB} MiB)" >&2
exit 1
