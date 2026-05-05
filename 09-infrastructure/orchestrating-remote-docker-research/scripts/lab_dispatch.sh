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

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lab.env"

SERVER=""
IMAGE=""
GPU=""
NAME=""
CMD=""
declare -a EXTRA_MOUNTS=()
MOUNT_WS=0
DETACH=1

usage() {
  sed -n '2,15p' "${BASH_SOURCE[0]}" >&2
  exit 2
}

# Positional first arg = server (allow either positional or --server)
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

_KEY="${SERVER//-/_}"
HOST_VAR="LAB_${_KEY}_HOST"
WS_VAR="LAB_${_KEY}_WORKSPACE"
HOST="${!HOST_VAR:-}"
WS_HOST_PATH="${!WS_VAR:-}"
[[ -z "$HOST" ]]   && { echo "ERROR: unknown server '$SERVER'" >&2; exit 2; }

declare -a MOUNT_ARGS=()
if (( MOUNT_WS )); then
  [[ -z "$WS_HOST_PATH" ]] && { echo "ERROR: LAB_${_KEY}_WORKSPACE not set" >&2; exit 2; }
  MOUNT_ARGS+=("-v" "$WS_HOST_PATH:${IN_CONTAINER_WORKSPACE:-/workspace}")
fi
for m in "${EXTRA_MOUNTS[@]}"; do
  MOUNT_ARGS+=("-v" "$m")
done

DETACH_FLAG="-d"
(( DETACH )) || DETACH_FLAG="--rm -i"

# Build the remote docker run command.
# We use "$@" array semantics by composing into a single quoted-and-shipped string.
REMOTE_CMD=$(printf '%q ' \
  docker run $DETACH_FLAG \
    --name "$NAME" \
    --gpus "\"device=$GPU\"" \
    --label "autoresearch.gpu=$GPU" \
    --label "autoresearch.server=$SERVER" \
    "${MOUNT_ARGS[@]}" \
    "$IMAGE" \
    bash -lc "$CMD")

# Special-case: --gpus expects bare device=N inside its own quotes; printf %q escapes the double-quotes which docker accepts.
ssh -o BatchMode=yes "$HOST" "$REMOTE_CMD"
