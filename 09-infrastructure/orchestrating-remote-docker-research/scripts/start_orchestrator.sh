#!/usr/bin/env bash
# start_orchestrator.sh — idempotently build and launch the persistent autoresearch
# orchestrator container on the control server.
#
# Run this on the control server (the one that runs the long-lived Claude Code session).
# It is safe to re-run: it rebuilds the image only if missing, and recreates the
# container only if its config changed.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# ---------- load config ----------
if [[ ! -f "$SCRIPT_DIR/lab.env" ]]; then
  echo "ERROR: $SCRIPT_DIR/lab.env not found. Copy from the template and edit it." >&2
  exit 1
fi
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lab.env"

: "${ORCHESTRATOR_NAME:?ORCHESTRATOR_NAME must be set in lab.env}"
: "${ORCHESTRATOR_IMAGE:?ORCHESTRATOR_IMAGE must be set in lab.env}"
: "${ORCHESTRATOR_WORKSPACE_HOST_PATH:?ORCHESTRATOR_WORKSPACE_HOST_PATH must be set in lab.env}"
: "${IN_CONTAINER_WORKSPACE:=/workspace}"
: "${HOST_CLAUDE_DIR:=$HOME/.claude}"
: "${HOST_SSH_DIR:=$HOME/.ssh}"

# ---------- sanity checks ----------
if ! command -v docker >/dev/null; then
  echo "ERROR: docker CLI not found on PATH. Are you on the control server?" >&2
  exit 1
fi
if ! docker info >/dev/null 2>&1; then
  echo "ERROR: cannot reach the docker daemon. Is your user in the docker group?" >&2
  exit 1
fi
if [[ ! -d "$ORCHESTRATOR_WORKSPACE_HOST_PATH" ]]; then
  echo "Workspace dir does not exist; creating: $ORCHESTRATOR_WORKSPACE_HOST_PATH"
  mkdir -p "$ORCHESTRATOR_WORKSPACE_HOST_PATH"
fi
if [[ ! -d "$HOST_CLAUDE_DIR" ]]; then
  echo "WARNING: $HOST_CLAUDE_DIR does not exist. Run 'claude' once on the host to log in," >&2
  echo "         or the orchestrator will need an ANTHROPIC_API_KEY in the environment." >&2
fi

# ---------- build image if missing ----------
DOCKERFILE="$ROOT_DIR/templates/orchestrator.Dockerfile"
if [[ ! -f "$DOCKERFILE" ]]; then
  echo "ERROR: $DOCKERFILE missing." >&2
  exit 1
fi

if ! docker image inspect "$ORCHESTRATOR_IMAGE" >/dev/null 2>&1; then
  echo "Building $ORCHESTRATOR_IMAGE ..."
  docker build \
    --build-arg HOST_UID="$(id -u)" \
    --build-arg HOST_GID="$(id -g)" \
    --build-arg HOST_USER="$(id -un)" \
    -t "$ORCHESTRATOR_IMAGE" \
    -f "$DOCKERFILE" \
    "$ROOT_DIR/templates"
fi

# ---------- compute extra mount args ----------
declare -a MOUNT_ARGS=()
if [[ -n "${ORCHESTRATOR_EXTRA_MOUNTS:-}" ]]; then
  IFS=',' read -ra _M <<< "$ORCHESTRATOR_EXTRA_MOUNTS"
  for m in "${_M[@]}"; do
    m="$(echo "$m" | xargs)"  # trim
    [[ -z "$m" ]] && continue
    host="${m%%:*}"
    if [[ ! -e "$host" ]]; then
      echo "WARNING: extra mount source $host does not exist; skipping."
      continue
    fi
    MOUNT_ARGS+=("-v" "$m")
  done
fi

# ---------- find docker group GID ----------
DOCKER_GID="$(getent group docker | cut -d: -f3 || true)"
if [[ -z "$DOCKER_GID" ]]; then
  echo "WARNING: no 'docker' group on host; orchestrator may lack socket access."
  DOCKER_GID="0"
fi

# ---------- env passthrough ----------
declare -a ENV_ARGS=()
if [[ -n "${ANTHROPIC_API_KEY:-}" ]]; then
  ENV_ARGS+=("-e" "ANTHROPIC_API_KEY=$ANTHROPIC_API_KEY")
fi

# ---------- recreate container ----------
if docker container inspect "$ORCHESTRATOR_NAME" >/dev/null 2>&1; then
  echo "Container $ORCHESTRATOR_NAME exists; removing for fresh start..."
  docker rm -f "$ORCHESTRATOR_NAME" >/dev/null
fi

# Build the user's home dir inside container so .claude / .ssh land in $HOME
USER_NAME="$(id -un)"
HOME_IN_CONTAINER="/home/$USER_NAME"

echo "Launching $ORCHESTRATOR_NAME ..."
docker run -d \
  --name "$ORCHESTRATOR_NAME" \
  --restart unless-stopped \
  --user "$(id -u):$(id -g)" \
  --group-add "$DOCKER_GID" \
  -v /var/run/docker.sock:/var/run/docker.sock \
  -v "$ORCHESTRATOR_WORKSPACE_HOST_PATH":"$IN_CONTAINER_WORKSPACE" \
  -v "$HOST_CLAUDE_DIR":"$HOME_IN_CONTAINER/.claude" \
  -v "$HOST_SSH_DIR":"$HOME_IN_CONTAINER/.ssh:ro" \
  "${MOUNT_ARGS[@]}" \
  "${ENV_ARGS[@]}" \
  -e HOME="$HOME_IN_CONTAINER" \
  -w "$IN_CONTAINER_WORKSPACE" \
  "$ORCHESTRATOR_IMAGE" \
  sleep infinity \
  >/dev/null

# Mirror the lab scripts into the workspace under .lab/ so the agent inside can call them.
LAB_DIR_IN_WS="$ORCHESTRATOR_WORKSPACE_HOST_PATH/.lab"
mkdir -p "$LAB_DIR_IN_WS"
cp -r "$ROOT_DIR/scripts/." "$LAB_DIR_IN_WS/"
chmod +x "$LAB_DIR_IN_WS"/*.sh 2>/dev/null || true

cat <<EOF

Started orchestrator container '$ORCHESTRATOR_NAME'.

Enter and start Claude Code:
  docker exec -it $ORCHESTRATOR_NAME tmux new-session -As research
  # inside tmux:
  claude

Helper scripts are mirrored at $LAB_DIR_IN_WS (in-container: $IN_CONTAINER_WORKSPACE/.lab).
Inspect with:
  docker logs --tail 20 $ORCHESTRATOR_NAME
  docker exec -it $ORCHESTRATOR_NAME bash
EOF
