# Architecture: Orchestrator + Workers via Docker-out-of-Docker

## Two-layer model

```
┌─────────────────── Control server (e.g. saitou) ──────────────────────┐
│                                                                          │
│   Host docker daemon ────────────────┬─────────────────────────────      │
│   /var/run/docker.sock               │                                   │
│       ▲                              │                                   │
│       │ DooD (mounted into orchestrator)                                 │
│       │                              │                                   │
│   ┌───┴────────────────────┐         │                                   │
│   │ Orchestrator container │         │ Sibling worker containers        │
│   │ - Claude Code (Node)   │ docker  │ ┌────────────────┐               │
│   │ - docker CLI           ├────────►│ │ exp_smoke_001  │ GPU 0          │
│   │ - ssh client           │ run     │ ├────────────────┤               │
│   │ - git, tmux, jq, etc.  │         │ │ exp_bringup_X  │ GPU 1          │
│   │ - python helpers       │         │ ├────────────────┤               │
│   │ - NO GPU               │         │ │ ...            │ GPU N          │
│   │ - NO PyTorch / CUDA    │         │ └────────────────┘               │
│   └────────────────────────┘         │                                   │
│       │                              │                                   │
│       │ ssh                          │                                   │
│       └──────────────────────────────┼─────────────────────────────      │
│                                      ▼                                   │
└──────────────────────────────────────────────────────────────────────────┘
        │
        │ ssh (passwordless, key-based)
        ▼
┌─────────────────── Worker server (e.g. saitou-h200) ───────────────────┐
│  Host docker daemon                                                    │
│      ▲                                                                 │
│      │ ssh + docker CLI on host                                        │
│      │                                                                 │
│  ┌───┴──────────────┐                                                  │
│  │ exp_long_ctx_h1  │ GPU 0                                            │
│  └──────────────────┘                                                  │
└────────────────────────────────────────────────────────────────────────┘
```

## Why DooD (not DinD)

**Docker-in-Docker** runs a full `dockerd` inside a container, typically with `--privileged`. It is rejected by most lab security policies and can corrupt the host's overlay filesystem.

**Docker-out-of-Docker** mounts the host's `/var/run/docker.sock` into the container. The in-container `docker` CLI talks to the *host's* daemon. No second daemon, no privileged mode. Containers spawned this way are **siblings** of the orchestrator on the host, not children.

## Data flow

| Source | Sink | Mechanism |
|---|---|---|
| Orchestrator → host daemon | docker run / build / ps / logs | Mounted `/var/run/docker.sock` |
| Orchestrator → remote host daemon | docker run / build / ps / logs | `ssh` to remote, then docker CLI uses remote's local socket |
| Worker → orchestrator | result files, metric CSVs | Shared NFS workspace, mounted in both |
| Orchestrator → worker | code, configs, Dockerfiles | Same shared NFS workspace |
| Worker → world | HuggingFace, arXiv, GitHub | Worker's own network namespace, outbound through host bridge |

## Identity and permissions

The orchestrator container runs as the **host user** (uid:gid passed via `--user`). The host's `docker` group GID is added with `--group-add`, granting access to `/var/run/docker.sock` (mode 660 root:docker). Files written to mounted volumes are owned by the host user, no `chown` cleanup needed.

Containers spawned via DooD inherit nothing from the orchestrator's user namespace — they run with whatever user their image specifies (typically root by default for ML images).

## State persistence

Three layers of state, with three different lifetimes:

| State | Where | Lifetime |
|---|---|---|
| Orchestrator process state (Claude Code session, tmux) | Inside the container's writable layer + tmux internal state | Killed on container restart |
| Orchestrator config, git state, lab scripts | Mounted volumes (workspace NFS, ~/.claude, ~/.ssh) | Persists across container/image rebuilds |
| Workers and their results | Sibling containers + workspace NFS | Workers ephemeral; results persistent on NFS |

Critical rule: **anything important must live in a mounted volume**, never in the container's writable layer. The orchestrator image must be reproducible from its Dockerfile alone.

## Cross-server dispatch

When the agent needs to run a worker on a remote server (e.g. saitou-h200), the orchestrator:

1. Looks up the SSH host alias from `lab.env` (`LAB_<server>_HOST`)
2. Runs `ssh <host> docker build/run` over the established SSH connection
3. The remote host's docker daemon executes the command
4. The worker's mounts use the **remote host's** workspace path (the NFS appears at different mount points on different hosts)
5. Results land in the shared NFS, automatically visible from the orchestrator

This requires:
- SSH passwordless access from orchestrator to remote (via `~/.ssh` mount with proper keys)
- `docker` CLI installed on remote host (typically already there)
- The shared NFS mounted on both ends with paths declared in `lab.env`

## Cleanup model

- Worker containers either (a) `--rm` (foreground, dies on completion) or (b) detached + manually `docker rm` after `lab_collect.sh` (default for long jobs)
- Orchestrator container is `--restart unless-stopped` and never deleted in normal operation
- Image cleanup is the user's responsibility — `docker image prune -a` periodically

## Failure modes the architecture is designed for

| Failure | Recovery |
|---|---|
| User SSH disconnects | Orchestrator + workers untouched, reconnect tmux |
| Tmux dies | Orchestrator container untouched, re-attach via `tmux new -A -s research` |
| Orchestrator container OOM/crashes | `--restart unless-stopped` brings it back automatically |
| Host reboot | docker daemon comes up, orchestrator auto-starts; tmux + Claude session must be re-launched |
| Worker crash | Logs and partial results in workspace; orchestrator polls and notices, retries or fails the experiment cleanly |
| NFS hiccup | Workers may stall on I/O; usually transient; orchestrator's filesystem watches handle it |
| Remote server unreachable | `lab_dispatch.sh` errors out; orchestrator retries or routes to another server |
