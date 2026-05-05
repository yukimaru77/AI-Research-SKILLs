---
name: orchestrating-remote-docker-research
description: Runs autoresearch on a remote Docker-only compute cluster using a persistent orchestrator container that dispatches per-experiment worker containers via Docker-out-of-Docker (DooD). Use when the only host operation permitted is docker, when the lab provides a small set of GPU servers reachable via SSH, when each experiment needs an isolated Dockerfile/image, and when state must persist across SSH disconnects and host reboots.
version: 1.0.0
author: Orchestra Research
license: MIT
tags: [Infrastructure, Remote Docker, DooD, Orchestrator, Multi-Server, GPU Scheduling, SSH, Lab Compute]
dependencies: []
---

# Orchestrating Remote Docker Research

A practical playbook for running autoresearch on a lab compute cluster where:
- the host OS is locked down (only `docker` operations are permitted),
- compute is split across one or more SSH-reachable GPU servers,
- each experiment may need its own Dockerfile / CUDA / PyTorch / library combo,
- the agent must survive SSH disconnects, host reboots, and 20-minute `/loop` ticks.

This skill defines a **two-layer container architecture**: a persistent **orchestrator container** running Claude Code on one designated server, dispatching ephemeral **worker containers** (on the same or other servers) via Docker-out-of-Docker (DooD, i.e. mounting `/var/run/docker.sock`). State, code, and results live on shared NFS so any server's worker reads/writes the same workspace.

## Architecture at a glance

```
[Orchestrator] persistent container on the designated control server
   │  Claude Code + node + docker CLI + ssh client + research helpers
   │  GPU not required
   │
   ├─→ docker run on local server      (worker container, GPU=N)
   └─→ ssh other-server "docker run"   (worker container on remote GPU)

[Workers] per-experiment, ephemeral containers
   - mount the shared NFS workspace
   - pinned to one GPU device
   - return results via the shared workspace
```

## When to use this skill

- Your lab gives you SSH to one or more GPU machines, and Docker is the only sanctioned execution path
- You cannot install software on the host (no apt, no system services)
- DooD is permitted (`/var/run/docker.sock` is rw to your group), but DinD is not
- Bring-Up of multiple components requires conflicting CUDA / PyTorch / library versions and you don't want to maintain a single mega-image
- You need experiments to keep running across SSH disconnects and host reboots

**Use a different infrastructure skill instead when**: you have a managed cloud GPU service (`modal-serverless-gpu`, `lambda-labs-gpu-cloud`, `skypilot-multi-cloud-orchestration`), or you have unrestricted host access (just run Claude Code on the host directly).

## Quick start

One-time setup (you run this on the control server). After this the orchestrator runs forever.

```bash
# 1. Clone this skill's templates onto the control server
ssh CONTROL_SERVER
git clone <this-fork>.git ~/AI-Research-SKILLs
cd ~/AI-Research-SKILLs/09-infrastructure/orchestrating-remote-docker-research

# 2. Edit scripts/lab.env to match your cluster (paths, server names, GPU counts)
$EDITOR scripts/lab.env

# 3. Build the orchestrator image and launch the persistent container
bash scripts/start_orchestrator.sh

# 4. Enter the orchestrator and start Claude
docker exec -it autoresearch tmux new-session -As research
# inside tmux:
claude
# → first prompt to autoresearch goes here
```

Templates and scripts referenced above:
- [`templates/orchestrator.Dockerfile`](templates/orchestrator.Dockerfile)
- [`templates/lab-environment.yaml`](templates/lab-environment.yaml) — drop into `research-state.yaml` `environment:` block
- [`scripts/start_orchestrator.sh`](scripts/start_orchestrator.sh)
- [`scripts/lab.env`](scripts/lab.env) — your cluster-specific config

## Common workflows

### Workflow 1: Dispatch a Bring-Up reproduction on the control server

```
Bring-Up Dispatch Checklist
- [ ] Step 1: Pick the right server (deciding logic below)
- [ ] Step 2: Write experiments/_bringup/{component}/Dockerfile
- [ ] Step 3: Build the image via lab_build_image.sh
- [ ] Step 4: Pick a free GPU via lab_gpu_pick.sh
- [ ] Step 5: Dispatch detached worker via lab_dispatch.sh
- [ ] Step 6: Poll via lab_status.sh; collect via lab_collect.sh
- [ ] Step 7: Record bringup_baseline in research-state.yaml
```

**Step 1: Pick the right server**

The agent decides directly (no `deep_thinker` mediation needed). Default rules:

| Workload shape | Pick |
|---|---|
| Single-GPU experiment, model fits in 40 GB, parallel sweeps wanted | Multi-GPU server (uses one device) |
| Single-GPU experiment, model needs >40 GB or long context | Single big-VRAM server |
| Distributed training across 2+ GPUs (FSDP, DeepSpeed, DDP) | Multi-GPU server only |
| Any experiment using libraries with mature multi-GPU support | Multi-GPU server (more total VRAM) |
| Quick smoke test / Bring-Up reproduction | Either; usually multi-GPU server has the spare slot |

**Per-server trade-off (write this into your lab-environment.yaml `notes:`)**:
- The multi-GPU A100-style server has more **total** VRAM (e.g. 8 × 40 GB = 320 GB) but you can only realize that via libraries that do multi-GPU well: PyTorch DDP/FSDP, DeepSpeed, Accelerate, Megatron-Core, vLLM tensor parallel, etc. Sharding-unaware code only sees 40 GB per process.
- The single big-GPU H200-style server is **simpler**: a vanilla `model.cuda()` already gets ~144 GB. No sharding, no NCCL, no rank coordination. Pick this when the experiment's library doesn't have well-tested multi-GPU support, or when you want to avoid distributed-training debugging entirely.

**Step 2: Write the Dockerfile**

```dockerfile
# experiments/_bringup/{component}/Dockerfile
FROM nvcr.io/nvidia/pytorch:24.10-py3
RUN pip install --no-cache-dir <pinned packages>
WORKDIR /workspace
```

**Step 3: Build**

```bash
# from inside orchestrator container
bash /workspace/.lab/lab_build_image.sh saitou \
  experiments/_bringup/{component}/Dockerfile \
  exp_{component}:latest
```

For builds on a remote server, the script SSHes to that server, copies the build context via rsync (or relies on the shared NFS), and runs `docker build` there.

**Step 4: Pick a free GPU**

```bash
GPU_ID=$(bash /workspace/.lab/lab_gpu_pick.sh saitou)
# returns an integer or exits non-zero if none free above the busy threshold
```

**Step 5: Dispatch detached worker**

```bash
CONTAINER_ID=$(bash /workspace/.lab/lab_dispatch.sh saitou \
  --image exp_{component}:latest \
  --gpu "$GPU_ID" \
  --name "exp_{component}_$(date +%s)" \
  --mount-workspace \
  --cmd "python /workspace/experiments/_bringup/{component}/run.py")
```

**Step 6: Poll and collect**

`/loop 20m` ticks call `lab_status.sh` to check progress. When done, `lab_collect.sh` snapshots logs + results into the shared workspace.

```bash
bash /workspace/.lab/lab_status.sh "$CONTAINER_ID"
# states: running | done(exit=0) | failed(exit=N) | gone
bash /workspace/.lab/lab_collect.sh "$CONTAINER_ID" \
  experiments/_bringup/{component}/results/
```

**Step 7: Record the baseline**

Append to `research-state.yaml`:

```yaml
bringup_baselines:
  {component}:
    server: saitou
    image: exp_{component}:latest
    metric: <value>
    source: <paper claim or repo README>
    invocation_script: src/bringup/{component}/run.sh
    verified_at: <ISO date>
```

### Workflow 2: Inner Loop experiment on the big-GPU server

Same shape as Workflow 1 but with `lab_dispatch.sh saitou-h200` and an experiment image extending one of the verified Bring-Up images.

```bash
GPU_ID=$(bash /workspace/.lab/lab_gpu_pick.sh saitou-h200)   # always 0 on a 1-GPU server
CONTAINER_ID=$(bash /workspace/.lab/lab_dispatch.sh saitou-h200 \
  --image exp_long_context_qwen:latest \
  --gpu "$GPU_ID" \
  --name "exp_H1_$(date +%s)" \
  --mount-workspace \
  --cmd "python /workspace/experiments/long-ctx-h1/run.py --batch 16")
```

The orchestrator continues with other work while this runs; on the next `/loop` tick it polls.

### Workflow 3: Parallel hyperparameter sweep across all GPUs of the multi-GPU server

```bash
for cfg in configs/sweep/*.yaml; do
  GPU_ID=$(bash /workspace/.lab/lab_gpu_pick.sh saitou) || break
  bash /workspace/.lab/lab_dispatch.sh saitou \
    --image exp_sweep:latest \
    --gpu "$GPU_ID" \
    --name "sweep_$(basename "$cfg" .yaml)" \
    --mount-workspace \
    --cmd "python /workspace/experiments/sweep-h2/run.py --config /workspace/$cfg" &
done
wait
```

This spawns up to N concurrent workers (one per free GPU). The script's GPU picker enforces single-tenant-per-device.

## Shared NFS workspace

The single most important property: **all workers and the orchestrator mount the same workspace path**, sourced from a shared NFS that every server in the cluster sees. Same files, same git state, same `research-state.yaml`.

Put this in `templates/lab-environment.yaml` and into your `research-state.yaml`:

```yaml
environment:
  shared_workspace_host_path:
    control_server: /shared/nfs/path/research          # path as the orchestrator host sees it
    other_server:   /possibly/different/mount/research # same NFS, different mount point
  in_container_workspace: /workspace                   # always this, on every container
```

`lab_dispatch.sh` reads this and emits the right `-v host_path:/workspace` per server.

## State persistence across reboots and disconnects

| Failure | What happens | Recovery |
|---|---|---|
| Your laptop disconnects | Orchestrator and workers keep running (they're on the server) | Reconnect SSH, re-attach tmux |
| Your tmux is killed | Orchestrator container keeps running | `docker exec -it autoresearch tmux new-session -As research && claude --resume` |
| Orchestrator container crashes | `--restart unless-stopped` brings it back | `start_orchestrator.sh` is idempotent |
| Control server reboots | Daemon comes up, orchestrator auto-restarts | Re-attach tmux; Claude needs a manual `claude --resume` |
| A worker container crashes mid-experiment | Logs and partial results remain in the workspace | Diagnose via `docker logs`, retry |

**Critical rule**: the orchestrator must NOT hold mutable state in its own writable layer. Everything important must be in mounted volumes (workspace, `~/.claude`, ssh keys). The orchestrator image must be reproducible from its Dockerfile alone.

## When to use vs alternatives

**Use this skill when**:
- The cluster is Docker-only and DooD is permitted
- You need different CUDA/PyTorch combos per component (Bring-Up is heavy)
- Your agent must survive disconnects and reboots
- You have multiple SSH-reachable GPU servers

**Use `09-infrastructure/modal-serverless-gpu` instead when**: you can spend money on serverless GPU and don't want to manage infra
**Use `09-infrastructure/skypilot-multi-cloud-orchestration` instead when**: you're shopping for spot pricing across cloud providers
**Use `09-infrastructure/lambda-labs-gpu-cloud` instead when**: you have Lambda credits and want simple SSH+persistent FS

## Common issues

**Issue: `docker: Got permission denied while trying to connect to the Docker daemon socket`**

Inside the orchestrator container, the user must be in a group whose GID matches the host's `docker` group GID (typically 998 or 987 on Ubuntu). Pass it at run time:

```bash
DOCKER_GID=$(getent group docker | cut -d: -f3)
docker run ... --group-add "$DOCKER_GID" ...
```

`start_orchestrator.sh` does this automatically.

**Issue: `--gpus` flag works on the host shell but fails inside the orchestrator**

The orchestrator dispatches `docker run --gpus ...` to the host daemon (via the mounted socket) — it does not itself need GPU access. If it fails, the host's `nvidia-container-toolkit` is misconfigured; ask the lab admin.

**Issue: experiment can't reach `huggingface.co` or `api.anthropic.com`**

Check by running `docker run --rm <image> curl -s -o /dev/null -w "%{http_code}\n" https://huggingface.co`. If it fails, the lab firewall is blocking outbound from container networks. Ask the admin to whitelist the orchestrator container's network.

**Issue: workspace files end up owned by `root`**

Run the orchestrator with `--user $(id -u):$(id -g)` matching your host UID/GID. The Dockerfile pre-creates a matching user. `start_orchestrator.sh` does this automatically.

**Issue: H200 / big-VRAM experiment runs out of memory despite "enough" total**

You're probably using a library that doesn't shard across GPUs. Either move the experiment to the single-big-GPU server, or switch to a multi-GPU-aware library (FSDP, DeepSpeed, vLLM tensor-parallel, Megatron). See `08-distributed-training/` skills.

**Issue: orchestrator's `/var/run/docker.sock` mount has wrong permissions after host reboot**

Some hosts re-create the socket with mode 660 root:root for a brief window. If `start_orchestrator.sh` fails right after a reboot, wait 30 s and retry.

## Advanced topics

**Architecture details**: See [references/architecture.md](references/architecture.md)
**Multi-server routing decisions**: See [references/multi-server-routing.md](references/multi-server-routing.md)
**Troubleshooting catalog**: See [references/troubleshooting.md](references/troubleshooting.md)

## Resources

- Docker DooD pattern: https://jpetazzo.github.io/2015/09/03/do-not-use-docker-in-docker-for-ci/
- nvidia-container-toolkit: https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/
