#!/usr/bin/env bash
# lab_build_image.sh SERVER DOCKERFILE_PATH IMAGE_TAG
#
# Build IMAGE_TAG on SERVER using DOCKERFILE_PATH (path inside the shared workspace).
# Build context is the directory of the Dockerfile.

set -euo pipefail

SERVER="${1:?usage: lab_build_image.sh SERVER DOCKERFILE_REL_PATH IMAGE_TAG}"
DOCKERFILE_REL="${2:?usage: lab_build_image.sh SERVER DOCKERFILE_REL_PATH IMAGE_TAG}"
TAG="${3:?usage: lab_build_image.sh SERVER DOCKERFILE_REL_PATH IMAGE_TAG}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lab.env"

_KEY="${SERVER//-/_}"
HOST_VAR="LAB_${_KEY}_HOST"
WS_VAR="LAB_${_KEY}_WORKSPACE"
HOST="${!HOST_VAR:-}"
WS="${!WS_VAR:-}"
[[ -z "$HOST" ]] && { echo "ERROR: unknown server $SERVER" >&2; exit 2; }
[[ -z "$WS"   ]] && { echo "ERROR: LAB_${_KEY}_WORKSPACE unset" >&2; exit 2; }

DF_HOST_ABS="$WS/$DOCKERFILE_REL"
CTX_HOST_ABS="$(dirname "$DF_HOST_ABS")"

ssh -o BatchMode=yes "$HOST" \
  "docker build -t $TAG -f $DF_HOST_ABS $CTX_HOST_ABS"

echo "Built $TAG on $SERVER"
