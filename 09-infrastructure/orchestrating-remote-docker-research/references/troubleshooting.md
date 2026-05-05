# Troubleshooting

Catalog of issues observed during setup and operation, with fixes.

## Setup-time issues

### `mkdir: cannot create directory ‘/raid/nonaka’: Permission denied`

`/raid` is owned by root with no per-user dirs created. Either:
- Ask the lab admin to `mkdir -p /raid/$USER && chown $USER:users /raid/$USER`, OR
- Drop `/raid/nonaka/scratch` from the workspace layout. Local NVMe scratch is optional — workers can use `/dev/shm` for hot data instead.

### `ssh: Could not resolve hostname saitou-h200: Name or service not known` (from inside saitou)

The user's laptop has `saitou-h200` defined in `~/.ssh/config` with a Tailscale IP, but saitou itself does not. Add to `~/.ssh/config` on saitou:

```
Host saitou-h200
  HostName <h200's reachable IP from saitou — typically the same Tailscale subnet, e.g. 10.8.213.20>
  User <your username>
  IdentityFile ~/.ssh/id_ed25519
  IdentitiesOnly yes
  StrictHostKeyChecking accept-new
```

Find h200's IP: from h200, run `ip addr show | grep 'inet '` and pick the IP in the same subnet as saitou's primary interface.

Then add saitou's `~/.ssh/id_ed25519.pub` to h200's `~/.ssh/authorized_keys`.

### `nonaka@192.168.201.1: Permission denied (publickey,password)`

192.168.201.1 is the *file server* (e.g. `saitohlab-h200-fs`), not the GPU node. NFS exports come from the FS, but ssh access is via the GPU node's IP. Use `hostname` on each candidate IP to identify which is which.

### Build fails because `docker compose` plugin missing on host

The orchestrator's Dockerfile installs `docker-compose-plugin`, so compose is available *inside the orchestrator container*. The host doesn't need it. If a worker needs compose, install it in that worker's image.

## Runtime issues

### `docker: Got permission denied while trying to connect to the Docker daemon socket`

Inside the orchestrator container, the user must be in a group whose GID matches the host's `docker` group GID. The `start_orchestrator.sh` script handles this with `--group-add "$(getent group docker | cut -d: -f3)"`. If you launched the container manually, re-launch with the script.

### `ssh: Could not resolve hostname saitou` (from inside orchestrator container)

The orchestrator runs ON saitou. There is no need to ssh to itself. The lab scripts use `_lab_lib.sh` which checks `CONTROL_SERVER` and runs locally when the target server is the control server. Confirm `lab.env` has `CONTROL_SERVER="saitou"` (or your control server's name).

### `nvidia-smi: command not found` from inside orchestrator container

By design — the orchestrator has no NVIDIA runtime. To query GPU state, `lab_gpu_pick.sh` runs a tiny `docker run --gpus all nvidia/cuda:...-base nvidia-smi ...` to ask the host's daemon. This works because of the mounted docker socket.

### Worker container OOM on the multi-GPU server, but not on single big-VRAM server

You've run into the "320 GB is aggregate" trap. The multi-GPU server has 8 × 40 = 320 GB total but each process only sees one device. Either (a) move the experiment to the single big-VRAM server (vanilla 144 GB), or (b) use a sharding library (FSDP, DeepSpeed, vLLM TP, Megatron-LM). See `multi-server-routing.md`.

### `Connection reset by peer` / `Connection timed out during banner exchange` to the laptop's SSH proxy host

If your laptop reaches the lab via a Windows proxy jump (Tailscale + Windows OpenSSH), the Windows OpenSSH server can become unresponsive under sustained connection churn. Symptoms: many parallel `ssh` calls leave stale `ssh -W ... ynona-win` proxy processes; eventually the Windows side rate-limits or stops accepting connections.

Mitigations:
- Avoid running many parallel SSH commands. Batch operations into a single shell snippet sent over one SSH connection.
- After a stall, kill stale SSH processes on your laptop (`pkill -9 -f 'ssh -W'`).
- If stalled connections persist on the Windows side, restart the OpenSSH service on Windows (`Restart-Service sshd` in admin PowerShell).
- Long-term fix: replace the Windows proxy with a Linux-based jump host or set up direct Tailscale routing.

This problem is **outside the orchestrator container** — it only affects how YOU reach saitou. The orchestrator and workers, once running, are unaffected.

### Worker container can't reach `huggingface.co` / `api.anthropic.com`

Test from inside a fresh worker:

```bash
docker run --rm <your-image> curl -s -o /dev/null -w "%{http_code}\n" https://huggingface.co
```

If it fails:
- The lab firewall may block container-network outbound. Ask the admin to whitelist the docker bridge subnet.
- The image may lack `ca-certificates`. Add `apt-get install ca-certificates` to the Dockerfile.
- DNS may fail. Test with `getent hosts huggingface.co` and add `--dns 8.8.8.8` to the run command if needed.

### Files in workspace owned by `root`

The container was launched without `--user $(id -u):$(id -g)`. Re-run `start_orchestrator.sh`, which sets this correctly. To fix existing root-owned files:

```bash
ssh saitou
sudo chown -R "$USER:users" /h200-home/nonaka/research/<offending-path>
```

(If you don't have sudo, ask the admin.)

### Claude Code says "Invalid authentication credentials" (401)

Your `.credentials.json` is stale. Run `claude login` inside the orchestrator container:

```bash
docker exec -it autoresearch tmux new-session -As research
claude
# follow the login flow; the file at ~/.claude/.credentials.json (mounted) will be refreshed
```

The mount is bidirectional, so the host's `~/.claude/.credentials.json` also updates — future container rebuilds will reuse the same auth.

### Orchestrator's `~/.claude.json` (config) is missing

This is a separate file from `~/.claude/` (note the trailing dot vs slash). Claude Code creates it on first login. If it's missing but `~/.claude/backups/` has old copies, it usually self-heals on the next `claude` invocation. Force-restore is rarely needed.

### Background SSH commands stuck in zombie state on the laptop

If `ps aux | grep ssh` shows many old `ssh -W ...` processes that don't exit, kill them by PID:

```bash
ps aux | grep "ssh -W" | awk '{print $2}' | xargs -r kill -9
```

Then wait a minute for the proxy host (Windows OpenSSH) to clear its accept queue before retrying.

## Diagnostics quick reference

```bash
# From your laptop:
ssh saitou 'echo OK'                       # baseline reachability
ssh saitou-h200 'echo OK'                  # remote worker server reachability

# From saitou shell:
docker ps                                  # all containers including autoresearch
docker exec autoresearch bash              # enter orchestrator
ssh saitou-h200 'echo OK'                  # cross-server (from saitou's user, not container)

# From inside orchestrator container:
docker ps                                  # via DooD; should show host's containers
ssh saitou-h200 'echo OK'                  # via mounted ~/.ssh
nvidia-smi                                 # FAILS by design — no GPU runtime in orchestrator
docker run --rm --gpus all nvidia/cuda:12.4.0-base-ubuntu22.04 nvidia-smi
                                           # OK — uses DooD to spawn a GPU-equipped sibling

# Quick lab check from container:
cd /workspace/.lab
bash lab_gpu_pick.sh saitou
bash lab_gpu_pick.sh saitou-h200
bash lab_status.sh --all
```
