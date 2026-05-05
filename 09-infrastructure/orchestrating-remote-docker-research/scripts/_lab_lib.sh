#!/usr/bin/env bash
# _lab_lib.sh — sourced by every lab_*.sh script. Provides:
#   on_server SERVER -- CMD ARG...
#     Executes CMD ARG... on SERVER. If SERVER matches $CONTROL_SERVER (i.e. the
#     orchestrator runs on this server's docker daemon), runs locally with bash.
#     Otherwise SSHes to LAB_<server>_HOST.
#
#   server_host SERVER
#     Echo the SSH host alias for SERVER, or empty if local.
#
#   require_server SERVER
#     Validate that SERVER is a configured lab server; exit non-zero otherwise.
#
# Note: when running locally on the control server (the case for the orchestrator
# container), `docker` commands talk to the HOST daemon via the mounted
# /var/run/docker.sock — that is exactly the same daemon that the SSH path would
# reach anyway. No GPU hardware access is required by the orchestrator itself;
# it only issues docker commands.

# Resolve the LAB_<server>_<key> env var for SERVER, replacing '-' with '_'.
_lab_var() {
  local server="$1" key="$2"
  local norm="${server//-/_}"
  local var="LAB_${norm}_${key}"
  printf '%s' "${!var:-}"
}

server_host() {
  local server="$1"
  if [[ "$server" == "${CONTROL_SERVER:-}" ]]; then
    printf ''
    return 0
  fi
  _lab_var "$server" HOST
}

require_server() {
  local server="$1"
  local host
  host="$(_lab_var "$server" HOST)"
  if [[ -z "$host" ]]; then
    echo "ERROR: unknown server '$server'. Configure LAB_${server//-/_}_HOST in lab.env." >&2
    return 2
  fi
  return 0
}

# on_server SERVER -- cmd args...
# Runs the command on SERVER. If SERVER is the control server, runs locally
# (bypassing SSH). Otherwise SSHes to LAB_<server>_HOST. The caller passes the
# command split into args; we re-quote properly.
on_server() {
  local server="$1"; shift
  if [[ "${1:-}" == "--" ]]; then shift; fi

  local host
  host="$(server_host "$server")"

  if [[ -z "$host" ]]; then
    # local execution
    "$@"
    return $?
  fi

  # remote execution; quote args for ssh
  local quoted=""
  for a in "$@"; do
    quoted+=" $(printf '%q' "$a")"
  done
  ssh -o BatchMode=yes -o ConnectTimeout=10 "$host" "bash -lc${quoted:+ }$(printf '%q' "$quoted")"
}

# on_server_sh SERVER 'shell snippet using $SERVER vars locally'
# Like on_server but takes a single shell snippet (no automatic quoting). Use
# when you need pipes / shell-builtins. Locally, runs via `bash -c`.
on_server_sh() {
  local server="$1" snippet="$2"
  local host
  host="$(server_host "$server")"

  if [[ -z "$host" ]]; then
    bash -c "$snippet"
    return $?
  fi
  ssh -o BatchMode=yes -o ConnectTimeout=10 "$host" "$snippet"
}
