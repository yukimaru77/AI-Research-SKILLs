#!/usr/bin/env bash
# lab_status.sh [SERVER|--all] [CONTAINER_NAME_OR_ID]
#
# Without args:           list all autoresearch.* containers across configured servers, with state.
# With SERVER:            list autoresearch.* containers on that server.
# With SERVER + container: print one of {running|done(exit=0)|failed(exit=N)|gone}.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lab.env"

list_for() {
  local server="$1"
  local key host
  key="${server//-/_}"
  host="LAB_${key}_HOST"
  host="${!host:-}"
  [[ -z "$host" ]] && return
  echo "=== $server ($host) ==="
  ssh -o BatchMode=yes "$host" \
    'docker ps -a --filter label=autoresearch.server --format "table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Label \"autoresearch.gpu\"}}"' \
    || echo "  (ssh failed)"
}

probe_one() {
  local server="$1" name="$2"
  local key host
  key="${server//-/_}"
  host="LAB_${key}_HOST"
  host="${!host:-}"
  [[ -z "$host" ]] && { echo "gone"; return; }
  if ! ssh -o BatchMode=yes "$host" "docker container inspect $name >/dev/null 2>&1"; then
    echo "gone"; return
  fi
  local state code
  state=$(ssh "$host" "docker inspect -f '{{.State.Status}}' $name")
  if [[ "$state" == "running" ]]; then
    echo "running"
  else
    code=$(ssh "$host" "docker inspect -f '{{.State.ExitCode}}' $name")
    if [[ "$code" == "0" ]]; then
      echo "done(exit=0)"
    else
      echo "failed(exit=$code)"
    fi
  fi
}

if (( $# == 0 )); then
  for s in $LAB_SERVERS; do list_for "$s"; done
elif (( $# == 1 )) && [[ "$1" == "--all" ]]; then
  for s in $LAB_SERVERS; do list_for "$s"; done
elif (( $# == 1 )); then
  list_for "$1"
elif (( $# == 2 )); then
  probe_one "$1" "$2"
else
  echo "usage: lab_status.sh [SERVER|--all] [CONTAINER_NAME]" >&2
  exit 2
fi
