---
name: simulating-experiment-runs-in-twins
description: META skill for running simulated experiment campaigns inside a validated ARA-versioned digital twin. Orchestrates parameter sweeps (SEM stage voltage/current/WD), protocol replay sequences, and batch RL training runs across MJX-vmapped and Isaac Lab parallel environments. Uses Hydra + Optuna + W&B for sweep config and tracking, Slurm/submitit for distributed A100 dispatch, and ARA Seal-Level provenance sidecars per trial. Dispatches physics to cat 27 (MuJoCo-MJX, Isaac Lab, Genesis, SAPIEN) and rendering to cat 26. Use after lab-equipment-twinning and versioning-twins-with-ara have produced a signed twin_package/ release.
version: 2.0.0
author: Orchestra Research
license: MIT
tags: [Digital Twin, Batch Simulation, Experiment Campaign, Hydra, Optuna, Weights and Biases, Slurm, MJX, Isaac Lab, ARA, SEM, Parameter Sweep, Protocol Replay, RL Training]
---

# Simulating Experiment Runs in Twins

META skill for running **experiment campaigns** inside a validated digital twin. Sits at the intersection of cat 23-27 infrastructure and ARA provenance. Receives a signed `twin_package/` from [lab-equipment-twinning](../lab-equipment-twinning/SKILL.md) and [versioning-twins-with-ara](../versioning-twins-with-ara/SKILL.md), then orchestrates three campaign modes:

| Campaign mode | Driver | Physics | Provenance |
|---|---|---|---|
| `param_sweep` | Optuna study | MJX vmap batched | ARA Seal L1 per trial |
| `protocol_replay` | Slurm array | MuJoCo/MJX deterministic | ARA trace + evidence |
| `batch_rl_training` | Isaac Lab + Ray/torchrun | Isaac Lab parallel envs | W&B + ARA checkpoint refs |

**You ROUTE** — cat 27 sub-skills execute physics, cat 26 sub-skills handle rendering/VR.

## Orchestration stack (2026 best practice)

Verified against May 2026 release state:

| Layer | Tool | Version / license | Role |
|---|---|---|---|
| Config composition | Hydra | 1.3.x, MIT | Compose sem/beam/stage/protocol yamls |
| Sweep optimizer | Optuna | 4.8.0 (Mar 2026), MIT | Trial suggestion, DB-backed study, pruning |
| Experiment tracker | W&B | Server v0.80 (Apr 2026), MIT SDK | Dashboards, artifact lineage, image compare |
| Multi-objective BO | Ax Platform | 1.2.4 (Mar 2026), MIT | Use only for constrained multi-objective SEM campaigns |
| Distributed runner | Slurm + submitit + Pyxis | — | Job arrays, Docker/Enroot containers, A100 dispatch |
| RL HPO | Ray Tune | Active | Isaac Lab HPO when dynamic scheduling needed |
| Postprocessing | Dask | — | CPU-heavy metric aggregation, not primary ledger |
| Provenance | ARA Seal Certificate | 2026-04 spec | Immutable sidecar per trial |

**Verdict**: Hydra + Optuna + W&B tracking is the 2026 maintenance leader for digital-twin sweeps. W&B Sweeps can be used for simple dashboards but should not own provenance or scheduling (see GitHub issue #7811 below).

## Architecture

```
[ versioning-twins-with-ara → signed twin_package_v{X.Y.Z}.tar.zst ]
        |
        v
simulating-experiment-runs-in-twins  (THIS SKILL — META)
   |
   |── param_sweep mode
   |     Hydra config → Optuna study → Slurm array (Pyxis A100)
   |     └─ per trial: MJX vmap rollout → metrics → ARA sidecar → W&B log
   |
   |── protocol_replay mode
   |     Slurm array (one task per protocol shard, deterministic seeds)
   |     └─ per shard: MuJoCo/MJX replay → ARA trace → evidence archive
   |
   |── batch_rl_training mode
   |     Isaac Lab num_envs=4096 → torchrun multi-GPU
   |     └─ per run: checkpoint ref → W&B artifact → ARA evidence link
   |
   └── dispatch physics to:
         27/simulating-mujoco-mjx          (MJX vmap sweeps)
         27/validating-isaac-sim-lab       (RL training, sensor-rich)
         27/prototyping-genesis-physics    (fast RL prototyping)
         27/calibrating-sysid-rl-hooks     (sim-real gap closure)
       dispatch rendering to:
         26/compiling-splat-assets
         26/publishing-supersplat-webxr
         26/deploying-quest-spatial-splats
```

## Workflow 1 — SEM stage parameter sweep (MJX vmap)

Goal: sweep voltage kV, beam current nA, working distance mm across N trials, score sharpness/dose/drift, record ARA provenance per trial.

Task Progress:
- [ ] SW1. Verify `twin_package/mujoco/sem_stage.xml` loads: `python -c "import mujoco; mujoco.MjModel.from_xml_path('twin_package/mujoco/sem_stage.xml')"`
- [ ] SW2. Smoke-test single MJX rollout locally before submitting arrays
- [ ] SW3. Create Optuna study: `python -m sem_twin.optuna_create_study --study sem_stage_v1 --storage postgresql://optuna-db/sem --direction maximize`
- [ ] SW4. Author `configs/sem/beam.yaml`, `configs/sem/stage.yaml`, `configs/campaign/sweep.yaml` (Hydra tree)
- [ ] SW5. Build immutable A100 container: `docker build -t registry.local/sem-twin:$(git rev-parse --short HEAD) -f docker/Dockerfile .`
- [ ] SW6. Submit Slurm array: `sbatch --array=0-511%32 --gres=gpu:a100:1 --container-image=... slurm/sem_optuna_array.sbatch`
- [ ] SW7. Each worker: ask Optuna trial → run MJX vmap batch → write `run_meta.json` + `seal_certificate.json` + `metrics.jsonl` → log to W&B
- [ ] SW8. Check throughput: `mjx-testspeed twin_package/mujoco/sem_stage.xml` (or `mjwarp-testspeed` for MJWarp backend)
- [ ] SW9. Known-impossible plan regression: open SEM chamber while `vacuum_state == pumped` must be rejected by preconditions
- [ ] SW10. After campaign: compile ARA artifact and review Seal Level achieved

**MJX vmap pattern** (SEM stage sweep):

```python
# sem_mjx_sweep.py — vectorized SEM stage parameter sweep on A100
import functools
import jax
import jax.numpy as jp
import mujoco
from mujoco import mjx

mj_model = mujoco.MjModel.from_xml_path("twin_package/mujoco/sem_stage.xml")
mx = mjx.put_model(mj_model)

def qpos_addr(name):
    jid = mujoco.mj_name2id(mj_model, mujoco.mjtObj.mjOBJ_JOINT, name)
    return int(mj_model.jnt_qposadr[jid])

STAGE_IDX = jp.array([qpos_addr(j) for j in
                       ["stage_x", "stage_y", "stage_z", "stage_tilt"]])

def sem_surrogate(qpos, voltage_kv, beam_current_na, working_distance_mm):
    """Validated SEM detector surrogate — replace with physics-backed model."""
    z, tilt = qpos[STAGE_IDX[2]], qpos[STAGE_IDX[3]]
    focus_err = z - working_distance_mm * 1e-3
    sharpness = jp.exp(-1e5 * focus_err**2) * jp.cos(tilt)**2
    dose = voltage_kv * beam_current_na
    drift_um = jp.linalg.norm(qpos[STAGE_IDX[:2]]) * 1e6
    return jp.array([sharpness, dose, drift_um])

def rollout_one(params, protocol_ctrl):
    # params = [kV, nA, WD_mm, x, y, z, tilt]
    d = mjx.make_data(mx)
    qpos = d.qpos.at[STAGE_IDX].set(params[3:7])
    d = d.replace(qpos=qpos)
    def step(d, ctrl_t):
        d = d.replace(ctrl=ctrl_t)
        return mjx.step(mx, d), None
    dT, _ = jax.lax.scan(step, d, protocol_ctrl)
    return sem_surrogate(dT.qpos, params[0], params[1], params[2])

@functools.partial(jax.jit)
def run_sem_batch(param_batch, protocol_ctrl):
    # param_batch: [N, 7], protocol_ctrl: [T, nu]
    return jax.vmap(rollout_one, in_axes=(0, None))(param_batch, protocol_ctrl)
```

**Known MuJoCo-MJX issue**: GitHub issue [#2288](https://github.com/google-deepmind/mujoco/issues/2288) (Dec 2024, closed) — `mjx.get_data()` fails when transferring batched MJX data back to CPU-side `mujoco.MjData` for rendering. Keep batched physics and rendering/export paths tested separately with CI smoke tests.

## Workflow 2 — Replay deposition protocol sequences

Goal: deterministically replay N protocol files across Slurm tasks, capture ARA trace per shard.

Task Progress:
- [ ] RP1. Enumerate protocol library: `ls twin_package/protocols/deposition/*.yaml | wc -l`
- [ ] RP2. Validate each protocol file has `preconditions`, `steps`, `effects`, `seed` fields
- [ ] RP3. Submit Slurm array with one task per protocol shard (deterministic seeds): `sbatch --array=0-{N-1} slurm/replay_array.sbatch`
- [ ] RP4. Each task: load protocol → run MuJoCo/MJX deterministic rollout → assert final state matches `effects` → write ARA trace
- [ ] RP5. Diff-check: if sim final state diverges from expected by >5 mm or >1°, flag for [calibrating-sysid-rl-hooks](../../27-physics-simulation/calibrating-sysid-rl-hooks/SKILL.md)
- [ ] RP6. Aggregate pass/fail rates across shards; archive `evidence/protocol_replay/` per ARA layout
- [ ] RP7. Re-run [validating-digital-twins](../validating-digital-twins/SKILL.md) regression gates after replay

Required outputs: `evidence/protocol_replay/{shard_id}/run_meta.json`, `seal_certificate.json`, `replay_diff.json`, `metrics.jsonl`.

## Workflow 3 — Batch RL training across parallel Isaac Lab envs

Goal: train SEM stage policy over 4096 parallel environments on A100, with ARA checkpoint provenance.

Task Progress:
- [ ] RL1. Register `SEM-Stage-Protocol-Replay-v0` task in `twin_package/isaaclab_tasks/`
- [ ] RL2. Configure `env_cfg.scene.sem.*` ranges (voltage, beam current, WD) and `env_cfg.scene.protocol.library_path`
- [ ] RL3. Single-GPU smoke: `./isaaclab.sh -p scripts/rsl_rl/train.py --task SEM-Stage-Protocol-Replay-v0 --num_envs 64 --headless`
- [ ] RL4. Multi-GPU launch: `torchrun --standalone --nnodes=1 --nproc_per_node=4 ./isaaclab.sh -p scripts/rsl_rl/train.py --task SEM-Stage-Protocol-Replay-v0 --num_envs 4096 --headless --distributed`
- [ ] RL5. Initialize W&B only on rank 0 — do NOT create `wandb.sweep()` inside distributed entrypoint (see issue #7811 below)
- [ ] RL6. Write ARA evidence link per checkpoint: `evidence/rl_training/{run_id}/checkpoint_refs.json`
- [ ] RL7. Evaluate trained policy against [calibrating-sysid-rl-hooks](../../27-physics-simulation/calibrating-sysid-rl-hooks/SKILL.md) for sim-real gap

**Isaac Lab parallel-env pattern**:

```python
# sem_isaaclab_vec_rl.py
from isaaclab.app import AppLauncher
app_launcher = AppLauncher({"headless": True})
simulation_app = app_launcher.app

import gymnasium as gym
import torch
from isaaclab_tasks.utils import parse_env_cfg
from isaaclab_rl.rsl_rl import RslRlVecEnvWrapper

TASK = "SEM-Stage-Protocol-Replay-v0"
env_cfg = parse_env_cfg(TASK, device="cuda:0", num_envs=4096, use_fabric=True)
env_cfg.scene.sem.voltage_kv_range = (2.0, 30.0)
env_cfg.scene.sem.beam_current_na_range = (0.01, 1.0)
env_cfg.scene.stage.working_distance_mm_range = (2.0, 15.0)
env_cfg.scene.protocol.library_path = "twin_package/protocols/deposition/"

env = RslRlVecEnvWrapper(gym.make(TASK, cfg=env_cfg, render_mode=None))
obs = env.reset()
for _ in range(128):
    actions = torch.zeros((env.num_envs, env.action_space.shape[0]), device=env.device)
    obs, rewards, dones, infos = env.step(actions)
env.close()
simulation_app.close()
```

**Known W&B + distributed issue**: GitHub issue [#7811](https://github.com/wandb/wandb/issues/7811) (Jun 2024, closed) — calling `wandb.sweep()` inside `torchrun` distributed entrypoint creates multiple sweep IDs. Create the Optuna study/W&B sweep **once outside DDP**; initialize W&B only on rank 0.

## ARA Seal-Level provenance

Every trial produces an immutable sidecar. Minimum required fields:

```json
{
  "ara_version": "2026-04",
  "run_id": "sem_20260505_000421_a13f9c2e",
  "artifact_id": "ara:sem-twin-campaign:2026-05-05",
  "seal_level_target": 1,
  "seal_level_achieved": 1,
  "parent_twin_package": {
    "path": "twin_package/",
    "ara_digest": "sha256:...",
    "physics_backend": "mujoco-mjx"
  },
  "orchestration": {
    "hydra_overrides": ["sem.voltage_kv=10", "sem.beam_current_na=0.1"],
    "optuna_study": "sem_stage_dose_sharpness_v1",
    "optuna_trial_number": 421,
    "slurm_job_id": "8431992_421",
    "wandb_run_path": "lab/sem-twin/runs/a13f9c2e"
  },
  "environment_hash": {
    "container_image_digest": "sha256:...",
    "git_commit": "...",
    "gpu": "NVIDIA A100",
    "mujoco": "3.8.0",
    "seed": 12345
  },
  "sem_parameters": {
    "voltage_kv": 10.0,
    "beam_current_na": 0.1,
    "working_distance_mm": 5.0
  },
  "evidence": {
    "metrics_jsonl": "evidence/runs/a13f9c2e/metrics.jsonl",
    "rendered_frames": "evidence/runs/a13f9c2e/frames/"
  }
}
```

ARA artifact layout:

```
ara/
  logic/
    claims.md
    experiments.md
  src/
    configs/
      sem_stage_sweep.yaml
  evidence/
    runs/{run_id}/
      run_meta.json
      seal_certificate.json
      metrics.jsonl
```

## 9-call CLI skeleton

```bash
# 1) Install ARA skills locally
npx @orchestra-research/ara-skills install --all --local

# 2) Build immutable A100 container
docker build -t registry.local/sem-twin:$(git rev-parse --short HEAD) -f docker/Dockerfile .

# 3) Smoke-test twin locally (single trial)
python -m sem_twin.run sim.backend=mjx campaign=smoke \
  sem.voltage_kv=10 sem.beam_current_na=0.1 sem.working_distance_mm=5.0 \
  ara.seal_level_target=1

# 4) Create Optuna study
python -m sem_twin.optuna_create_study \
  --study sem_stage_dose_sharpness_v1 \
  --storage postgresql://optuna:optuna@optuna-db/sem \
  --direction maximize

# 5) Submit Slurm array (param sweep)
sbatch --array=0-511%32 --gres=gpu:a100:1 \
  --container-image=registry.local/sem-twin:$(git rev-parse --short HEAD) \
  --container-mounts=$PWD:/workspace \
  slurm/sem_optuna_array.sbatch

# 6) Worker: ask Optuna → MJX rollout → ARA sidecar → W&B log
python -m sem_twin.worker \
  --study sem_stage_dose_sharpness_v1 \
  --storage postgresql://optuna:optuna@optuna-db/sem \
  --trial-index ${SLURM_ARRAY_TASK_ID} \
  --ara-root ara/ --wandb-project sem-twin

# 7) Benchmark MJX throughput on SEM model
mjx-testspeed twin_package/mujoco/sem_stage.xml

# 8) Launch Isaac Lab RL batch training (multi-GPU)
torchrun --standalone --nnodes=1 --nproc_per_node=4 \
  ./isaaclab.sh -p scripts/reinforcement_learning/rsl_rl/train.py \
  --task SEM-Stage-Protocol-Replay-v0 --num_envs 4096 --headless --distributed

# 9) Compile and review ARA artifact post-campaign
# /compiler twin_package/ ara/evidence/runs/ --output ara/sem_campaign_2026_05_05
# /rigor-reviewer ara/sem_campaign_2026_05_05
```

## Quality gates

| Gate | Pass threshold | Fail action |
|---|---|---|
| MJX vmap smoke test | Completes without NaN | Re-check model XML; see [simulating-mujoco-mjx](../../27-physics-simulation/simulating-mujoco-mjx/SKILL.md) |
| `mjx.get_data()` round-trip | Per-trial selected frames transfer cleanly | Keep batched physics + rendering paths separate (issue #2288) |
| ARA sidecar present per trial | 100% of trials | Worker failure; check Slurm logs |
| Optuna study-level reproducibility | Same seed → same metric ±1e-6 | Fix non-determinism; pin CUDA/JAX seeds |
| Protocol replay final-state match | ≤5 mm / ≤1° vs expected | Re-calibrate via [calibrating-sysid-rl-hooks](../../27-physics-simulation/calibrating-sysid-rl-hooks/SKILL.md) |
| Isaac Lab env step-time | ≥4096 env-steps/s on A100 | Reduce physics complexity; check use_fabric=True |
| W&B rank-0 only init | No duplicate run IDs | Fix distributed init order (issue #7811) |
| Known-impossible plan rejection | 100% rejected | Tighten preconditions; add regression test |
| Cross-engine endpoint disagreement | ≤5 mm | Reconcile coordinate frames |

## Common issues

| Symptom | Cause | Fix |
|---|---|---|
| `mjx.get_data()` fails on batched data | Issue #2288 — vmap batch dim not stripped on transfer | Call `mjx.get_data(mx, d[i])` on individual index, not full batch |
| Multiple W&B run IDs in torchrun | `wandb.init()` called on all ranks | Guard with `if rank == 0:` or use `WANDB_MODE=disabled` on non-zero ranks |
| Optuna study not found across workers | Each worker created own study | Create study once before `sbatch`; workers call `optuna.load_study()` |
| MJX NaN after JAX recompile | Non-static field changed between batches | Keep model structure fixed; only vary qpos/ctrl via vmap |
| Isaac Lab crash with `use_fabric=True` | USD stage fabric incompatible with task | Set `use_fabric=False` for debugging; re-enable after isolating |
| Slurm array tasks exceed Optuna budget | N tasks > n_trials | Set `n_trials` in study; workers exit cleanly when budget exhausted |
| ARA digest mismatch across nodes | Container not pinned by digest | Always reference container by `sha256:` digest, not tag |
| Protocol replay diverges >5 mm | Sim-real gap or seed not fixed | Pin `seed` in protocol YAML; see [calibrating-sysid-rl-hooks](../../27-physics-simulation/calibrating-sysid-rl-hooks/SKILL.md) |

## Lab automation case studies (2024-2026)

- **Digital Twin for Chemical Science (DTCS)** — Berkeley Lab / NERSC (2025, Nature Computational Science): bidirectional feedback loop between theory and APXPS experiment; predicts spectra, infers kinetics in real-time, guides experiments until stopping condition met. Directly analogous to using SEM twin to steer parameter sweeps before touching real hardware.
- **Rainbow autonomous nanocrystal synthesis** (2025, Nature Communications): digital twin ran virtual BO / Pareto-front campaigns to tune orchestration structure and LHS/BO allocation, then ran autonomous experimental campaigns across target energies. Pattern: twin-first campaign policy validation before real robot.
- **MatteriX robotic chemistry lab twin** (2025, arXiv): multi-scale GPU-accelerated twin covering robotic manipulation, powder/liquid dynamics, device functions, heat transfer, with sim-to-real transfer. Closest public pattern to a physics/robotics lab-equipment twin with in-silico workflow testing.

## Cross-references

### Cat 28 — digital twin workflows
- [lab-equipment-twinning](../lab-equipment-twinning/SKILL.md) — prerequisite orchestrator
- [validating-digital-twins](../validating-digital-twins/SKILL.md) — runtime gates
- [versioning-twins-with-ara](../versioning-twins-with-ara/SKILL.md) — signed release prerequisite

### Cat 27 — physics simulation
- [simulating-mujoco-mjx](../../27-physics-simulation/simulating-mujoco-mjx/SKILL.md) — MJX vmap sweeps
- [validating-isaac-sim-lab](../../27-physics-simulation/validating-isaac-sim-lab/SKILL.md) — RL training, sensor-rich
- [prototyping-genesis-physics](../../27-physics-simulation/prototyping-genesis-physics/SKILL.md) — fast RL prototyping
- [validating-sapien-articulations](../../27-physics-simulation/validating-sapien-articulations/SKILL.md) — articulated-object scenes
- [calibrating-sysid-rl-hooks](../../27-physics-simulation/calibrating-sysid-rl-hooks/SKILL.md) — sim-real gap
- [authoring-urdf-mjcf-usd](../../27-physics-simulation/authoring-urdf-mjcf-usd/SKILL.md) — model authoring
- [conditioning-collision-meshes](../../27-physics-simulation/conditioning-collision-meshes/SKILL.md) — collision proxies

### Cat 26 — 3D rendering / VR
- [compiling-splat-assets](../../26-3d-rendering-vr/compiling-splat-assets/SKILL.md)
- [publishing-supersplat-webxr](../../26-3d-rendering-vr/publishing-supersplat-webxr/SKILL.md)
- [deploying-quest-spatial-splats](../../26-3d-rendering-vr/deploying-quest-spatial-splats/SKILL.md)
- [rendering-unity-splats](../../26-3d-rendering-vr/rendering-unity-splats/SKILL.md)
- [rendering-unreal-xscene-splats](../../26-3d-rendering-vr/rendering-unreal-xscene-splats/SKILL.md)
- [editing-supersplat-scenes](../../26-3d-rendering-vr/editing-supersplat-scenes/SKILL.md)

### Cat 25 — affordance / VLM
- [vlm-physics-validation-loop](../../25-affordance-vlm/vlm-physics-validation-loop/SKILL.md) — reconcile affordance/joint mismatches

### Cat 24 — 3D segmentation / articulation
- [screwsplat-articulation](../../24-3d-segmentation-articulation/screwsplat-articulation/SKILL.md)
- [multistate-diff-open3d](../../24-3d-segmentation-articulation/multistate-diff-open3d/SKILL.md)

### Cat 23 — 3D reconstruction
- [training-gaussian-splats](../../23-3d-reconstruction/training-gaussian-splats/SKILL.md) — visual twin source
- [extracting-gs-surfaces](../../23-3d-reconstruction/extracting-gs-surfaces/SKILL.md)

### External
- MuJoCo 3.8.0 (Apr 2026), Apache-2.0 — [github.com/google-deepmind/mujoco](https://github.com/google-deepmind/mujoco)
- MuJoCo-MJX / MJWarp (JAX/Warp GPU backend) — same repo, v3.8.0.1 Apr 2026
- Optuna 4.8.0 (Mar 2026), MIT — [github.com/optuna/optuna](https://github.com/optuna/optuna)
- W&B Server v0.80 (Apr 2026) — [github.com/wandb/wandb](https://github.com/wandb/wandb)
- Ax Platform 1.2.4 (Mar 2026), MIT — constrained multi-objective BO
- submitit — lightweight Python Slurm interface
- Pyxis / Enroot — unprivileged Docker containers in Slurm
- Ray Tune — Isaac Lab HPO and dynamic scheduling
