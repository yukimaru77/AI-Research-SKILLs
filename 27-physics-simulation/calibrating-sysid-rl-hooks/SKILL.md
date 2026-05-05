---
name: calibrating-sysid-rl-hooks
description: Calibrates sim parameters (joint friction, damping, motor gains, contact friction) to match real lab measurements using Optuna outer-loop search, scipy.optimize local refinement, and optional JAX-differentiable paths. Exposes Gymnasium-compatible reset/step/obs/action/info wrappers without implementing a full RL stack. Use when a digital twin needs dynamics tuned to real rollouts and clean hooks into RSL-RL/RL-Games/skrl/SB3 RL fine-tuning pipelines; do NOT use when the task is reward shaping, end-to-end policy training, or mesh repair.
version: 2.0.0
author: Orchestra Research
license: Apache-2.0
tags: [Physics Simulation, System Identification, MuJoCo, Gymnasium, RL Hooks, Calibration, Optuna, SciPy]
dependencies: [mujoco>=3.8.0, gymnasium>=1.3.0, numpy>=2.0, scipy>=1.17.1, optuna>=4.8.0]
---

# calibrating-sysid-rl-hooks

## Quick start

Stack baseline (Deep_thinker verified May 2026):

| Package | Version | Released | License |
|---|---|---|---|
| mujoco | 3.8.0 | 2026-04 | Apache-2.0 |
| gymnasium | 1.3.0 | 2026-04-22 | MIT |
| scipy | 1.17.1 | 2026-02-23 | BSD |
| optuna | 4.8.0 | 2026-03-16 | MIT |
| bayesian-optimization | 3.2.1 | 2026-03-16 | MIT |
| rsl-rl-lib | 5.2.0 | 2026-04-23 | BSD-3 |
| stable-baselines3 | 2.8.0 | 2026-04-01 | MIT |
| rl-games | 1.6.5 | 2026-02-20 | MIT |
| optax | 0.2.8 | 2026-03-20 | Apache-2.0 |

**Recommended sysID framework for articulated lab equipment (2026): Optuna** — persistent studies, ask/tell interface for async hardware loops, multi-objective support, best maintenance signal. Use `scipy.optimize` for local numerical refinement. JAXopt (0.8.5, Apr 2025) has weaker 2026 maintenance and an open callback-compatibility bug (#636); avoid unless the objective is fully JAX-differentiable.

```bash
python3.11 -m venv .venv-sysid
source .venv-sysid/bin/activate
pip install --upgrade pip wheel setuptools
pip install "mujoco==3.8.0" "gymnasium==1.3.0" "numpy>=2.0" \
            "scipy>=1.17.1" "optuna>=4.8.0"
# Optional RL backends (pick one)
pip install "rsl-rl-lib==5.2.0"        # PPO, Isaac Lab first-class, BSD-3
# pip install "rl-games==1.6.5"        # PPO/SAC/A2C, Isaac Lab supported
# pip install "stable-baselines3==2.8.0"
```

## Common workflows

### 1. Joint friction + damping sysid (Optuna outer loop + scipy polish)

```
Task Progress:
- [ ] Step 1: Record real free-swing trajectory: release angle, qpos at ≥100 Hz
- [ ] Step 2: Build MuJoCo model with placeholder frictionloss + damping values
- [ ] Step 3: Define forward(params) → sim qpos trace; guard against NaN with finite check
- [ ] Step 4: Define loss = MSE(sim_trace, real_trace) on aligned timestamps
- [ ] Step 5: Optuna outer loop (TPE sampler, 50-100 trials) for global search
- [ ] Step 6: Polish best trial with scipy.optimize.minimize (method="SLSQP") + bounds
- [ ] Step 7: Validate fit on held-out trajectory; compute RMS residual
- [ ] Step 8: Persist calibrated values in model XML and sysid JSON record
```

MuJoCo joints expose `frictionloss` (Coulomb) and `damping` (viscous). For lab knobs, door hinges, and linear actuators these two parameters explain most sim-to-real discrepancy. Optuna's ask/tell API is especially useful when each evaluation hits real hardware instead of a fast sim.

```python
import numpy as np, mujoco, optuna
from scipy.optimize import minimize

real_t = np.load("real_t.npy")
real_q = np.load("real_q.npy")

model = mujoco.MjModel.from_xml_path("lab_arm.xml")
data  = mujoco.MjData(model)
j_id  = mujoco.mj_name2id(model, mujoco.mjtObj.mjOBJ_JOINT, "joint1")
T     = len(real_t)

def simulate(fr: float, damp: float) -> np.ndarray:
    model.dof_frictionloss[j_id] = max(fr, 0.0)
    model.dof_damping[j_id]      = max(damp, 0.0)
    mujoco.mj_resetData(model, data)
    data.qpos[j_id] = real_q[0]
    log = np.zeros(T)
    for t in range(T):
        mujoco.mj_step(model, data)
        if not np.all(np.isfinite(data.qpos)):
            return np.full(T, 1e6)   # stiff-system guard
        log[t] = data.qpos[j_id]
    return log

def optuna_objective(trial: optuna.Trial) -> float:
    fr   = trial.suggest_float("frictionloss", 0.0, 5.0)
    damp = trial.suggest_float("damping",      0.0, 50.0)
    return float(np.mean((simulate(fr, damp) - real_q) ** 2))

study = optuna.create_study(direction="minimize",
                             sampler=optuna.samplers.TPESampler(seed=42))
study.optimize(optuna_objective, n_trials=80, show_progress_bar=True)

best = study.best_params
# Local polish with SciPy SLSQP
res = minimize(lambda p: float(np.mean((simulate(*p) - real_q)**2)),
               x0=[best["frictionloss"], best["damping"]],
               method="SLSQP",
               bounds=[(0.0, 5.0), (0.0, 50.0)],
               options={"ftol": 1e-8, "maxiter": 300})
print("frictionloss={:.4f}  damping={:.4f}  MSE={:.2e}".format(*res.x, res.fun))
```

### 2. Multi-parameter contact friction sysid (differential evolution + least_squares)

```
Task Progress:
- [ ] Step 1: Tilted-stage slip test: record start-to-stop displacement at known tilt angle
- [ ] Step 2: Define 3-vector friction target (sliding, torsional, rolling) on geom pair
- [ ] Step 3: Global search with scipy.optimize.differential_evolution (workers=-1 for multicore)
- [ ] Step 4: Polish finalist with scipy.optimize.least_squares + Jacobian
- [ ] Step 5: Re-validate in full MuJoCo (not MJX) — MJX has restricted contact geometry
- [ ] Step 6: Patch <geom friction="..."/> in canonical MJCF; record sysid JSON
```

```python
from scipy.optimize import differential_evolution, least_squares

def residual(friction_vec, geom_id, model, data, target_disp):
    model.geom_friction[geom_id] = np.maximum(friction_vec, 0.0)
    # ... run slip-test sim, return scalar displacement
    sim_disp = run_slip_sim(model, data)
    return [sim_disp - target_disp]

bounds = [(0.01, 2.0), (0.001, 0.5), (0.001, 0.5)]
de_result = differential_evolution(
    lambda x: np.sum(np.array(residual(x, geom_id, model, data, target))**2),
    bounds=bounds, workers=-1, seed=0, maxiter=200, tol=1e-6)

ls_result = least_squares(
    residual, de_result.x,
    args=(geom_id, model, data, target),
    bounds=([0]*3, [2.0, 0.5, 0.5]),
    method="trf")
print("sliding={:.4f}  torsional={:.4f}  rolling={:.4f}".format(*ls_result.x))
```

### 3. Gymnasium env wrapper with sysID hooks for RL fine-tuning

```
Task Progress:
- [ ] Step 1: Subclass gymnasium.Env; declare observation_space and action_space
- [ ] Step 2: Load calibrated sysid JSON in __init__; apply params to MjModel
- [ ] Step 3: reset(seed=...) -> (obs, info); include sysid posteriors in info["sysid"]
- [ ] Step 4: step(action) -> (obs, reward=0.0, terminated, truncated, info)
- [ ] Step 5: Support domain randomization: sample params ± sigma around calibrated mean
- [ ] Step 6: render() via mujoco.Renderer (offscreen EGL only in headless envs)
- [ ] Step 7: Register env; pass to RSL-RL/RL-Games/SB3 trainer — no RL imports inside env
```

Gymnasium 1.3.0 requires 5-tuple step `(obs, reward, terminated, truncated, info)` and 2-tuple reset `(obs, info)`. The skill's wrapper does NOT define reward content — leave that to the consuming RL skill. Propagate sysid metadata in `info` so downstream randomization is reproducible.

```python
import json, numpy as np, gymnasium as gym, mujoco
from gymnasium import spaces
from pathlib import Path

class LabEquipmentEnv(gym.Env):
    metadata = {"render_modes": ["rgb_array"], "render_fps": 60}

    def __init__(self, xml_path: str, sysid_json: str | None = None,
                 domain_rand_sigma: float = 0.05, render_mode: str | None = None):
        super().__init__()
        self.model = mujoco.MjModel.from_xml_path(xml_path)
        self.data  = mujoco.MjData(self.model)
        self.render_mode = render_mode
        self._sysid_params: dict = {}
        self._rand_sigma = domain_rand_sigma

        if sysid_json and Path(sysid_json).exists():
            record = json.loads(Path(sysid_json).read_text())
            p = record.get("parameters", {})
            j = mujoco.mj_name2id(self.model, mujoco.mjtObj.mjOBJ_JOINT,
                                   record.get("joint", ""))
            if j >= 0:
                if "frictionloss" in p:
                    self.model.dof_frictionloss[j] = p["frictionloss"]
                if "damping" in p:
                    self.model.dof_damping[j] = p["damping"]
            self._sysid_params = p

        nu, nq = self.model.nu, self.model.nq
        self.action_space      = spaces.Box(-1.0, 1.0, shape=(nu,), dtype=np.float32)
        self.observation_space = spaces.Box(-np.inf, np.inf,
                                             shape=(2 * nq,), dtype=np.float32)
        self._renderer = None

    def _obs(self) -> np.ndarray:
        return np.concatenate([self.data.qpos, self.data.qvel]).astype(np.float32)

    def reset(self, *, seed=None, options=None):
        super().reset(seed=seed)
        mujoco.mj_resetData(self.model, self.data)
        # Optional domain randomization around calibrated mean
        sampled = {}
        rng = self.np_random
        for k, v in self._sysid_params.items():
            sampled[k] = float(rng.normal(v, abs(v) * self._rand_sigma))
        info = {"sysid": {"calibrated": self._sysid_params, "sampled": sampled}}
        return self._obs(), info

    def step(self, action):
        self.data.ctrl[:] = np.clip(action, -1.0, 1.0)
        mujoco.mj_step(self.model, self.data)
        terminated = truncated = False
        # reward intentionally 0.0 — caller defines reward
        return self._obs(), 0.0, terminated, truncated, {}

    def render(self):
        if self._renderer is None:
            self._renderer = mujoco.Renderer(self.model, 640, 480)
        self._renderer.update_scene(self.data)
        return self._renderer.render()
```

### 4. Isaac Lab RL fine-tuning integration

Isaac Lab (May 2026) integrates RSL-RL, RL-Games, SKRL, and SB3 as RL backends — there is no single native Isaac Lab PPO/SAC. PPO is first-class via RSL-RL and RL-Games; SAC requires RL-Games or SKRL. For articulated lab equipment, use RSL-RL PPO.

```
Task Progress:
- [ ] Step 1: Export calibrated MuJoCo XML → convert/adapt to Isaac Lab USD asset
- [ ] Step 2: Register task with calibrated sysid params in Isaac Lab env config
- [ ] Step 3: Wrap observation/action spaces to match RSL-RL expectations
- [ ] Step 4: Train with RSL-RL PPO: ./isaaclab.sh -p scripts/reinforcement_learning/rsl_rl/train.py --task MyLabTask
- [ ] Step 5: If SAC required: switch to RL-Games backend (rl_games/train.py)
- [ ] Step 6: Validate sim2real transfer with held-out real rollouts
```

```bash
# RSL-RL PPO (recommended for articulated equipment)
./isaaclab.sh -p scripts/reinforcement_learning/rsl_rl/train.py \
  --task Isaac-MyLabTask-v0 --num_envs 4096 --headless

# RL-Games PPO/SAC (if SAC is required)
./isaaclab.sh -p scripts/reinforcement_learning/rl_games/train.py \
  --task Isaac-MyLabTask-v0 --headless
```

## When to use vs alternatives

Use this skill when: (a) a digital twin needs calibrated dynamics matching real lab measurements, (b) parameter posteriors must be reproducibly recorded for pipeline orchestration, or (c) the asset must expose Gymnasium 1.x hooks without inheriting an opinionated RL framework.

| Scenario | Recommended tool |
|---|---|
| 1-3 parameter calibration, fast sim | `scipy.optimize.minimize` (Nelder-Mead or SLSQP) |
| 3-10 parameter, expensive sim or hardware-in-loop | **Optuna** outer loop + scipy polish |
| Low-dim, fully continuous, expensive black-box | `bayesian-optimization` (BayesianOptimization 3.2.1) |
| Differentiable JAX simulator | `optax` gradient descent; avoid jaxopt unless trust-constr not needed |
| RL fine-tuning (PPO, Isaac Lab) | RSL-RL 5.2.0 |
| RL fine-tuning (SAC required) | RL-Games 1.6.5 or SKRL |
| Broad algorithm coverage, non-Isaac | Stable-Baselines3 2.8.0 |
| Mesh/inertia issues | `conditioning-collision-meshes` skill |
| Full RL policy training | `cat-14 agents` / separate RL skill |

Do NOT: write reward functions here, train policies end-to-end, or duplicate RL framework logic inside the env wrapper.

## Common issues

**frictionloss vs damping confusion**: `frictionloss` is Coulomb friction (constant); `damping` is viscous (velocity-proportional). Calibrating both simultaneously without multiple trajectory regimes can collapse to one parameter. Fit damping first on small-amplitude oscillations, frictionloss second on stop-and-go trajectories, or ensure both regimes appear in the loss.

**Optimizer collapses to zero or diverges**: Always pass explicit `bounds` to all optimizers. Use `max(x, 0.0)` guards inside `forward()`. For Optuna, set `suggest_float(..., low=0.0)` rather than clipping after the fact. Log the full Optuna study with `study.trials_dataframe()` to detect degenerate loss surfaces.

**NaN on stiff systems during sweeps**: When sweeping `frictionloss` near zero on stiff hinges, `mj_step` can produce NaN. Guard with `if not np.all(np.isfinite(data.qpos)): return 1e9` before logging; this keeps all optimizers (Optuna, SciPy, DE) stable.

**Gymnasium 0.x vs 1.x API split**: Old code returns 4-tuple `(obs, reward, done, info)`; Gymnasium 1.x returns 5-tuple and reset returns `(obs, info)`. Lock to `gymnasium>=1.3.0`. SB3 2.8.0 supports the new API; RSL-RL and RL-Games use their own wrappers but accept Gymnasium 1.x envs.

**Domain randomization without reproducibility**: Store the seed and sampled sysid parameters in `info["sysid"]["sampled"]` every reset. Tests must replay the same seed and recover identical rollouts (MuJoCo CPU is deterministic given the same seed; MJX/JAX may differ bitwise).

**JAXopt trust-constr failure (issue #636, open Sep 2025)**: `jaxopt.ScipyMinimize` with `method="trust-constr"` fails due to a two-argument callback assumption. Workaround: use `method="BFGS"` or `method="L-BFGS-B"` inside JAXopt, or route constrained problems through `scipy.optimize.minimize` directly.

**Isaac Lab "built-in PPO/SAC" mismatch (issue #3960, closed Nov 2025)**: The project generator may show PPO-only for some backends. SAC is available via RL-Games or SKRL, not RSL-RL's core PPO path. Verify the template before expecting SAC support in a generated Isaac Lab project.

## Sysid result schema

Persist every calibration result as JSON so downstream pipeline orchestration can reuse it without re-running the loop:

```json
{
  "asset": "out/lab_arm/lab_arm.xml",
  "asset_hash": "sha256:...",
  "joint": "joint1",
  "parameters": {"frictionloss": 0.061, "damping": 0.473},
  "bounds": {"frictionloss": [0.0, 5.0], "damping": [0.0, 50.0]},
  "loss": 4.2e-5,
  "n_evals": 80,
  "optimizer": "optuna-TPE+scipy-SLSQP",
  "evidence": {
    "trajectory": "real_swing_2026-05-04.npz",
    "trajectory_hash": "sha256:..."
  },
  "validation": {"held_out_rms": 8.1e-4, "passed": true},
  "tooling": {"mujoco": "3.8.0", "scipy": "1.17.1",
               "optuna": "4.8.0", "gymnasium": "1.3.0"}
}
```

Schema is intentionally narrow: calibrate and report here; downstream RL/policy work consumes the JSON. Do not add reward shaping, demonstration content, or policy weights to this schema.

## Advanced topics

- See `references/issues.md` for: Optuna ask/tell interface patterns for hardware-in-loop sysID, JAXopt callback bug workarounds, Gymnasium 1.x migration details, and the canonical sysid result schema.
- See `references/api.md` for: full `scipy.optimize` API reference for least_squares/minimize/differential_evolution, Optuna sampler comparison (TPE vs CMA-ES vs GP), and MuJoCo 3.5+ sysid toolbox entry points.

## Resources

- MuJoCo: https://github.com/google-deepmind/mujoco
- MuJoCo sysid toolbox: https://mujoco.readthedocs.io/en/stable/programming/sysid.html
- Optuna: https://github.com/optuna/optuna
- SciPy optimize: https://docs.scipy.org/doc/scipy/reference/optimize.html
- bayesian-optimization: https://github.com/bayesian-optimization/BayesianOptimization
- Gymnasium: https://gymnasium.farama.org
- RSL-RL: https://github.com/leggedrobotics/rsl_rl
- RL-Games: https://github.com/Denys88/rl_games
- Stable-Baselines3: https://github.com/DLR-RM/stable-baselines3
- Isaac Lab RL comparison: https://isaac-sim.github.io/IsaacLab/main/source/overview/reinforcement-learning/rl_existing_scripts.html
- Optax: https://github.com/google-deepmind/optax
