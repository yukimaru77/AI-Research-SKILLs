#!/usr/bin/env bash
# lab_gpu_pick.sh SERVER [MIN_FREE_MIB]
#
# Pick a free GPU index on SERVER. "Free" means free memory >= MIN_FREE_MIB
# AND no other autoresearch worker container is currently bound to that device.
# Prints the chosen GPU index to stdout. Exits non-zero if no GPU qualifies.
#
# Used by autoresearch before lab_dispatch.sh.
#
# When SERVER is the control server (orchestrator's host), GPU info is queried
# by running a minimal --gpus all docker container, since the orchestrator
# container itself does not have the NVIDIA runtime installed.

set -euo pipefail

SERVER="${1:?usage: lab_gpu_pick.sh SERVER [MIN_FREE_MIB]}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lab.env"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/_lab_lib.sh"

require_server "$SERVER"

THRESHOLD_DEFAULT="${GPU_BUSY_FREE_MIB_THRESHOLD:-2000}"
MIN_FREE_MIB="${2:-$THRESHOLD_DEFAULT}"

# Free memory per GPU. On the control server we still call nvidia-smi via the
# host (DooD): a tiny docker run --gpus all --rm container exposes nvidia-smi.
GPU_QUERY_IMG="${GPU_QUERY_IMAGE:-nvidia/cuda:12.4.0-base-ubuntu22.04}"

if [[ -z "$(server_host "$SERVER")" ]]; then
  # local control server: use docker
  mapfile -t GPU_FREE < <(docker run --rm --gpus all "$GPU_QUERY_IMG" \
    nvidia-smi --query-gpu=index,memory.free --format=csv,noheader,nounits 2>/dev/null)
else
  mapfile -t GPU_FREE < <(on_server_sh "$SERVER" \
    "nvidia-smi --query-gpu=index,memory.free --format=csv,noheader,nounits")
fi

if [[ ${#GPU_FREE[@]} -eq 0 ]]; then
  echo "ERROR: nvidia-smi returned no GPUs on $SERVER" >&2
  exit 3
fi

# GPU indices currently held by autoresearch-launched containers (label set by lab_dispatch.sh).
mapfile -t HELD < <(on_server_sh "$SERVER" \
  'docker ps --filter label=autoresearch.gpu --format "{{.Label \"autoresearch.gpu\"}}"' \
  2>/dev/null || true)

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
