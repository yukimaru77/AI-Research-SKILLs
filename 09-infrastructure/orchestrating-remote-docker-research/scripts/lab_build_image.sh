#!/usr/bin/env bash
# lab_build_image.sh SERVER DOCKERFILE_REL_PATH IMAGE_TAG
#
# Build IMAGE_TAG on SERVER using DOCKERFILE_REL_PATH (path RELATIVE to the
# shared workspace root, e.g. "experiments/_bringup/foo/Dockerfile").
# Build context is the directory of the Dockerfile.

set -euo pipefail

SERVER="${1:?usage: lab_build_image.sh SERVER DOCKERFILE_REL_PATH IMAGE_TAG}"
DOCKERFILE_REL="${2:?usage: lab_build_image.sh SERVER DOCKERFILE_REL_PATH IMAGE_TAG}"
TAG="${3:?usage: lab_build_image.sh SERVER DOCKERFILE_REL_PATH IMAGE_TAG}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lab.env"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/_lab_lib.sh"

require_server "$SERVER"

WS="$(_lab_var "$SERVER" WORKSPACE)"
[[ -z "$WS" ]] && { echo "ERROR: LAB_${SERVER//-/_}_WORKSPACE unset" >&2; exit 2; }

DF_HOST_ABS="$WS/$DOCKERFILE_REL"
CTX_HOST_ABS="$(dirname "$DF_HOST_ABS")"

on_server_sh "$SERVER" "docker build -t $TAG -f $DF_HOST_ABS $CTX_HOST_ABS"

echo "Built $TAG on $SERVER"
