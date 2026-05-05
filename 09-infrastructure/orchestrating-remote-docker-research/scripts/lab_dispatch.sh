#!/usr/bin/env bash
# lab_dispatch.sh SERVER --image IMG --gpu N --name NAME [--mount-workspace] [--mount HOST:CONTAINER ...] --cmd "..."
#
# Dispatch a worker container on SERVER, pinned to GPU index N.
# Prints the resulting container ID on stdout. Container runs detached.
#
# Conventions enforced:
#   - container is labeled autoresearch.gpu=<N>      (so lab_gpu_pick.sh sees it)
#   - container is labeled autoresearch.server=<S>   (for status queries)
#   - workspace mount uses LAB_<server>_WORKSPACE when --mount-workspace is set
#
# When SERVER is the control server, runs `docker run` locally (no SSH),
# talking to the host daemon via the mounted /var/run/docker.sock.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lab.env"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/_lab_lib.sh"

SERVER=""
IMAGE=""
GPU=""
NAME=""
CMD=""
declare -a EXTRA_MOUNTS=()
MOUNT_WS=0
DETACH=1

usage() {
  sed -n '2,16p' "${BASH_SOURCE[0]}" >&2
  exit 2
}

if [[ $# -ge 1 && "$1" != --* ]]; then
  SERVER="$1"; shift
fi

while (( $# > 0 )); do
  case "$1" in
    --server)           SERVER="$2"; shift 2 ;;
    --image)            IMAGE="$2"; shift 2 ;;
    --gpu)              GPU="$2"; shift 2 ;;
    --name)             NAME="$2"; shift 2 ;;
    --cmd)              CMD="$2"; shift 2 ;;
    --mount-workspace)  MOUNT_WS=1; shift ;;
    --mount)            EXTRA_MOUNTS+=("$2"); shift 2 ;;
    --foreground)       DETACH=0; shift ;;
    -h|--help)          usage ;;
    *)                  echo "unknown arg: $1" >&2; usage ;;
  esac
done

[[ -z "$SERVER" || -z "$IMAGE" || -z "$GPU" || -z "$NAME" || -z "$CMD" ]] && usage

require_server "$SERVER"

WS_HOST_PATH="$(_lab_var "$SERVER" WORKSPACE)"

declare -a MOUNT_ARGS=()
if (( MOUNT_WS )); then
  [[ -z "$WS_HOST_PATH" ]] && { echo "ERROR: LAB_${SERVER//-/_}_WORKSPACE not set" >&2; exit 2; }
  MOUNT_ARGS+=("-v" "$WS_HOST_PATH:${IN_CONTAINER_WORKSPACE:-/workspace}")
fi
for m in "${EXTRA_MOUNTS[@]}"; do
  MOUNT_ARGS+=("-v" "$m")
done

DETACH_FLAGS="-d"
(( DETACH )) || DETACH_FLAGS="--rm -i"

# Build a single shell snippet — runs locally on control server, or via ssh otherwise.
# We escape arguments with %q to be safe through shell.
_DOCKER_RUN_ARGS=("docker" "run" $DETACH_FLAGS \
  "--name" "$NAME" \
  "--gpus" "\"device=$GPU\"" \
  "--label" "autoresearch.gpu=$GPU" \
  "--label" "autoresearch.server=$SERVER")
for ma in "${MOUNT_ARGS[@]}"; do
  _DOCKER_RUN_ARGS+=("$ma")
done
_DOCKER_RUN_ARGS+=("$IMAGE" "bash" "-lc" "$CMD")

quoted=""
for a in "${_DOCKER_RUN_ARGS[@]}"; do
  quoted+=" $(printf '%q' "$a")"
done

# trim leading space
SNIPPET="${quoted# }"

on_server_sh "$SERVER" "$SNIPPET"
