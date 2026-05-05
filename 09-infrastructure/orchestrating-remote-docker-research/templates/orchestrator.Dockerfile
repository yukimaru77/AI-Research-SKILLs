# syntax=docker/dockerfile:1
# Persistent orchestrator container for autoresearch on a Docker-only lab cluster.
#
# Contents:
#   - Ubuntu 24.04 base
#   - Node.js 20.x (Claude Code runtime)
#   - Claude Code CLI (@anthropic-ai/claude-code)
#   - docker CLI + compose plugin + buildx plugin (talks to HOST daemon via /var/run/docker.sock)
#   - git, ssh client, tmux, rsync, jq
#   - Python 3 + research helpers (semanticscholar, arxiv, habanero, requests, pyyaml)
#
# Build:
#   docker build \
#     --build-arg HOST_UID=$(id -u) \
#     --build-arg HOST_GID=$(id -g) \
#     --build-arg HOST_USER=$(id -un) \
#     -t research-orchestrator:latest \
#     -f orchestrator.Dockerfile .
#
# This image does NOT run any daemon. It only runs as a long-lived shell that
# holds a tmux session for Claude Code. Experiment containers are spawned as
# SIBLINGS by the host daemon (Docker-out-of-Docker, DooD).

FROM ubuntu:24.04

ARG DEBIAN_FRONTEND=noninteractive
ARG HOST_UID=1000
ARG HOST_GID=1000
ARG HOST_USER=researcher

# ---------- Base packages ----------
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    gnupg \
    git \
    openssh-client \
    rsync \
    tmux \
    jq \
    less \
    vim-tiny \
    python3 \
    python3-pip \
    python3-venv \
    sudo \
    && rm -rf /var/lib/apt/lists/*

# ---------- Node.js 20.x and Claude Code ----------
RUN curl -fsSL https://deb.nodesource.com/setup_20.x | bash - \
    && apt-get install -y --no-install-recommends nodejs \
    && rm -rf /var/lib/apt/lists/* \
    && npm install -g @anthropic-ai/claude-code \
    && npm cache clean --force

# ---------- Docker CLI + compose + buildx (no daemon) ----------
RUN install -m 0755 -d /etc/apt/keyrings \
    && curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
       | gpg --dearmor -o /etc/apt/keyrings/docker.gpg \
    && chmod a+r /etc/apt/keyrings/docker.gpg \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
        https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo $VERSION_CODENAME) stable" \
       > /etc/apt/sources.list.d/docker.list \
    && apt-get update \
    && apt-get install -y --no-install-recommends \
        docker-ce-cli \
        docker-compose-plugin \
        docker-buildx-plugin \
    && rm -rf /var/lib/apt/lists/*

# ---------- Python research helpers ----------
RUN pip3 install --no-cache-dir --break-system-packages \
    semanticscholar \
    arxiv \
    habanero \
    requests \
    pyyaml

# ---------- Host-matching user ----------
# Create a user matching the host UID/GID so files in mounted workspaces are owned correctly.
# If a group/user with the requested IDs already exists, reuse them silently.
RUN if ! getent group "$HOST_GID" >/dev/null; then \
        groupadd -g "$HOST_GID" "$HOST_USER"; \
    fi \
    && if ! id -u "$HOST_UID" >/dev/null 2>&1; then \
        useradd -m -u "$HOST_UID" -g "$HOST_GID" -s /bin/bash "$HOST_USER"; \
    fi \
    && (echo "$HOST_USER ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/$HOST_USER || true) \
    && chmod 0440 /etc/sudoers.d/$HOST_USER || true

# Convenience: friendly bashrc for the user
RUN _U=$(getent passwd "$HOST_UID" | cut -d: -f1 || echo researcher) \
    && _H=$(getent passwd "$HOST_UID" | cut -d: -f6 || echo /home/researcher) \
    && mkdir -p "$_H" \
    && cat >> "$_H/.bashrc" <<'EOF'
export PS1="\[\e[1;32m\]autoresearch\[\e[0m\]:\w$ "
alias ll='ls -la'
alias dps='docker ps --format "table {{.Names}}\t{{.Image}}\t{{.Status}}"'
EOF

# ---------- Working dir ----------
WORKDIR /workspace

# Default command keeps the container alive forever so docker exec / tmux can attach.
CMD ["sleep", "infinity"]
