---
name: articulation-ditto-prior
description: Provides before/after point-cloud articulation hypothesis generation using the Ditto CVPR 2022 prior (UT-Austin-RPL/Ditto, MIT). Operates exclusively as a SIDECAR validator — never the primary estimator — alongside multistate-diff-open3d in cat 24. Use for in-distribution furniture-like classes (cabinet doors, drawers, laptop-lid-style hinges, microwave/oven/toaster doors); treat all lab-equipment classes (SEM stages, microscope revolvers, optical benches, rotary filter wheels) as out-of-distribution and skip Ditto entirely.
version: 2.0.0
author: Orchestra Research
license: MIT
tags: [Articulation, Point Cloud, CVPR 2022, Legacy Stack, MIT, Sidecar Validator, Ditto]
dependencies: [python==3.8, torch==1.10.2, cudatoolkit==11.3, pytorch-lightning==1.5.4, torchmetrics==0.4.1, setuptools==59.5.0, hydra-core==1.1.0.rc1, hydra-colorlog==1.1.0.dev1, hydra-optuna-sweeper==1.1.0.dev2, open3d==0.12.0, pybullet==2.7.9, numpy==1.21.6, pykdtree==1.3.0, torch-scatter==2.0.9]
---

# Articulation prior with Ditto (sidecar validator)

Ditto (UT-Austin-RPL/Ditto, MIT, CVPR 2022, last commit 2024-12-20) consumes two point clouds
(before and after state of the same object) and predicts part segmentation, joint type
(revolute = 0 or prismatic = 1), joint axis, and pivot point. The released artifact is a
Hydra + PyTorch Lightning 1.5 research repo — not a maintained pip library. For the
lab-equipment digital-twin agent **Ditto is a SIDECAR validator only**. The primary
articulation estimator is `multistate-diff-open3d` in category 24. Ditto's role is to
generate an independent hypothesis and flag agreement or disagreement; it never overrides
the primary.

**Key constraints from the 2025/2026 upstream state:**
- One confirmed open-source environment: Python 3.8 + PyTorch 1.10.2 + CUDA 11.3 + Open3D
  0.12.0 + PyBullet 2.7.9 + Lightning 1.5.4. No maintained modern fork exists.
- Upstream issue #18 (Apr 2025): custom prismatic joints predicted as revolute using
  `Ditto_s2m.ckpt`. Treat joint-type output as uncalibrated outside training categories.
- Upstream issue #17 (Apr 2025): `numpy==1.9.5` pin in requirements.txt conflicts with
  Lightning's numpy requirement. Patch to `numpy==1.21.6` (last NumPy line for Python 3.8).
- No `scripts/predict.py`. Entry points are `run.py` (train) and `run_test.py` (test).
- Checkpoints are on UT Austin Box, not GitHub Releases. GitHub has no releases or tags.

## Quick start

Ditto must live in its own Docker container — its pin set is incompatible with every modern
Python/CUDA combination. Build the container once, freeze the image, and call it as a
subprocess from the agent.

```dockerfile
FROM nvidia/cuda:11.3.1-cudnn8-devel-ubuntu20.04
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y \
    build-essential git wget bzip2 ca-certificates \
    libgl1-mesa-glx libglib2.0-0 libx11-6 libxext6 libsm6 libxrender1 \
    && rm -rf /var/lib/apt/lists/*
```

```bash
# Inside the container — full install recipe (see references/issues.md for rationale)
git clone https://github.com/UT-Austin-RPL/Ditto.git && cd Ditto

# Patch numpy pin before installing (issue #17)
sed -i 's/numpy==1.9.5/numpy==1.21.6/' requirements.txt

conda create -n Ditto-py38 python=3.8 "pip<24.1" -y
conda activate Ditto-py38

conda install -y -c pytorch -c conda-forge \
  cudatoolkit=11.3 pytorch=1.10.2 torchvision pytorch-scatter

pip install -r requirements.txt
python scripts/convonet_setup.py build_ext --inplace
```

Download pretrained weights from UT Austin Box (not GitHub Releases):
- Shape2Motion checkpoint: `https://utexas.box.com/s/a4h001b3ciicrt3f71t4xd3wjsm04be7`
  → save as `Ditto_s2m.ckpt`
- Synthetic checkpoint: `https://utexas.box.com/s/zbf5bja20n2w6umryb1bcfbbcm3h2ysn`
  → save as `Ditto_syn.ckpt` (filename inferred; verify after download)

Smoke-test with the Shape2Motion laptop category:

```bash
python run_test.py \
  experiment=Ditto_s2m \
  trainer.resume_from_checkpoint=/abs/path/to/Ditto_s2m.ckpt \
  data_dir=/abs/path/to/Ditto/data \
  datamodule.opt.test.data_path='["Shape2Motion/laptop_test_standard"]'
```

Always use absolute paths — Hydra changes the working directory during runs.

## Common workflows

### Workflow 1: Cross-validate a revolute hypothesis (cabinet door)

The geometric spine (`multistate-diff-open3d`) has already returned `revolute` with a hinge
axis and angle. This workflow runs Ditto on the same point-cloud pair and checks agreement.

**Task Progress**
- [ ] Gate on in-distribution class: object must resemble laptop/oven/microwave/cabinet/faucet
- [ ] Sample 8192 points from each state via `gsplat-scene-adapter` (opacity-weighted, visibility-filtered)
- [ ] Normalize both clouds to shared bounding box: `center = bbox_center(pc0, pc1)`, `scale = max_bbox_extent * 1.1`; record inverse transform
- [ ] Run Ditto inference and collect `quant.npz` output
- [ ] Map Ditto axis/pivot back to world frame using saved inverse transform
- [ ] Compare: axis-angle error, pivot distance, joint-type match
- [ ] Emit cross-validation record and apply policy table (see "When to use vs alternatives")

```python
# Normalization that matches GeoArtDatasetV0 (norm_padding=0.1)
def normalize_pair(pc0, pc1):
    all_pts = np.vstack([pc0, pc1])
    center = (all_pts.max(0) + all_pts.min(0)) / 2
    scale = (all_pts.max(0) - all_pts.min(0)).max() * 1.1
    return (pc0 - center) / scale, (pc1 - center) / scale, {"center": center, "scale": scale}

def to_world(axis, pivot, meta):
    # axis is a direction — only normalization changed, direction unchanged
    pivot_world = pivot * meta["scale"] + meta["center"]
    return axis, pivot_world
```

```python
# Minimal programmatic API (internal, not a stable public interface)
from hydra import initialize, compose
from hydra.utils import instantiate
import torch, numpy as np

with initialize(config_path="configs"):
    cfg = compose("config.yaml", overrides=["experiment=Ditto_s2m"])

model = instantiate(cfg.model)
ckpt = torch.load("/abs/path/to/Ditto_s2m.ckpt", map_location="cpu")
model.load_state_dict(ckpt["state_dict"], strict=True)
model = model.eval().cuda()

pc0 = torch.as_tensor(pc0_norm, dtype=torch.float32).unsqueeze(0).cuda()  # (1, 8192, 3)
pc1 = torch.as_tensor(pc1_norm, dtype=torch.float32).unsqueeze(0).cuda()

with torch.no_grad():
    c = model.model.encode_inputs(pc0, pc1)
    logits_jt, param_rev, param_pris = model.model.decode_joints(query_pts, c)

p_prismatic = logits_jt.sigmoid().mean().item()
joint_type = "prismatic" if p_prismatic > 0.5 else "revolute"
confidence_proxy = max(p_prismatic, 1.0 - p_prismatic)
```

Sign-ambiguity note: commit `33276b6` fixed axis-direction sign; compare both `+axis` and
`-axis` against the primary estimator to avoid false disagreements.

### Workflow 2: Validate prismatic call (drawer)

Drawers are Ditto's best prismatic case (synthetic `drawer` training category). Use this
workflow when the primary estimator returns `prismatic` for a drawer-like part.

**Task Progress**
- [ ] Confirm part class is `drawer`-like (slide range > 3 cm, motion nearly linear)
- [ ] Sample 8192 points per state; normalize with shared bbox (Workflow 1 normalization)
- [ ] Run `run_test.py experiment=Ditto_syn` with `Ditto_syn.ckpt`
- [ ] Read `quant.npz`: check `joint_type` field (0=revolute, 1=prismatic)
- [ ] If `joint_type==1` and axis-angle error < 15 deg: emit `SUPPORT`
- [ ] If `joint_type==0` (revolute) despite drawer-like motion: flag issue #18 known failure; emit `ABSTAIN`, not contradiction
- [ ] Record `confidence_proxy = max(p_prismatic, 1-p_prismatic)` — treat as uncalibrated

```bash
python run_test.py \
  experiment=Ditto_syn \
  trainer.resume_from_checkpoint=/abs/path/to/Ditto_syn.ckpt \
  data_dir=/abs/path/to/data \
  datamodule.opt.test.data_path='["syn/drawer_test_standard"]' \
  model.opt.hparams.test_res=32
```

Output files written to `results/0000/`: `static.obj`, `mobile.obj`, `bounding_box.json`,
`out.urdf`, `quant.npz`. The `quant.npz` fields used by the agent: `joint_type`,
`joint_axis`, `pivot_point`, `config`.

### Workflow 3: OOD gate — skip Ditto for lab equipment

All SEM stages, microscope objective revolvers, rotary filter wheels, optical mounts, and
precision XY stages are **out of distribution**. This workflow gates Ditto before any
inference call.

**Task Progress**
- [ ] Read part class label from upstream semantic segmentation (LUDVIG/SAGA mask)
- [ ] Check against in-distribution allowlist (see "When to use vs alternatives")
- [ ] If OOD: write `{"ditto_skipped": "out_of_distribution"}` to cross-validation record and STOP
- [ ] If geometrically similar to an in-distribution class but OOD label (e.g. optical-bench cover shaped like a lid): run Ditto with `min_type_confidence` raised to 0.90 and label result `approximate_match`
- [ ] If in-distribution: proceed to Workflow 1 or 2

## When to use vs alternatives

**Ditto role in this codebase: SIDECAR validator only — never primary.**

The primary path for articulation in category 24 is `multistate-diff-open3d`.
Ditto is called after the primary returns a hypothesis and only for in-distribution classes.

**In-distribution allowlist** (released training categories only):

| Source | Categories |
|--------|-----------|
| Shape2Motion | laptop, oven, faucet, cabinet |
| Synthetic | cabinet2\_rand, drawer, microwave, toaster |

Lab-equipment classification:

| Lab object | Status | Sidecar behavior |
|-----------|--------|-----------------|
| Hinged instrument cover (cabinet-like) | Near-OOD | Allow; require agreement |
| Drawer-like sample tray | Closest prismatic match | Allow; issue #18 warning applies |
| Simple knob/valve (faucet-like) | Near-OOD | Allow with 0.85 confidence floor |
| Microscope objective revolver | OOD | Skip; abstain |
| Rotary filter wheel | OOD | Skip; abstain |
| Precision XY stage | OOD-prismatic | Skip; issue #18 failure mode |
| Rack-and-pinion focus | OOD compound | Skip; screw/gear, not simple joint |
| Multi-link arm | OOD | Skip; single-joint model only |
| Transparent covers / glassware | OOD sensor | Skip; poor depth quality |

**Sidecar decision policy:**

| Primary result | Ditto result | Action |
|---------------|-------------|--------|
| revolute, conf > 0.7 | revolute, axis-angle < 15 deg | `SUPPORT` — promote to `confidence_strong` |
| revolute, conf > 0.7 | prismatic | `CONTRADICTS_WITH_LOW_TRUST` — downgrade, request extra state |
| prismatic, conf > 0.7 | prismatic, axis-angle < 15 deg | `SUPPORT` — promote to `confidence_strong` |
| prismatic, conf > 0.7 | revolute | `CONTRADICTS_WITH_LOW_TRUST` — issue #18; do not auto-flip |
| ambiguous | any | Trust Ditto only if in-distribution AND confidence proxy > 0.85 |
| any | OOD class | `ABSTAIN` — write `ditto_skipped: out_of_distribution` |

Never auto-replace the primary with Ditto output. High-confidence Ditto contradiction on
OOD classes is not authoritative.

**Alternatives to Ditto (2025/2026):**

- `multistate-diff-open3d` (cat 24): primary estimator — use first always.
- RPMArt / RoArtNet (MIT): modern point-cloud articulation, no full mesh/URDF export.
  Best next candidate if Ditto's category coverage is too narrow.
- PARIS (MIT): NeRF-based two-state articulation — strong alternative but image/NeRF
  pipeline, not a point-cloud drop-in.
- SplArt, REArtGS (MIT): 3DGS pipelines for 2025/2026; not drop-in for point-cloud pairs.
- ScrewNet: screw-theory articulation from depth; older, uncertain maintenance.

## Common issues

See `references/issues.md` for full GitHub issue history and workarounds.

**`numpy==1.9.5` conflict (issue #17, Apr 2025).** The upstream `requirements.txt` pins
ancient NumPy. Patch before install: `sed -i 's/numpy==1.9.5/numpy==1.21.6/' requirements.txt`.
NumPy 1.21.6 is the last 1.x line with clean Python 3.8 support.

**Prismatic-to-revolute misclassification (issue #18, Apr 2025).** Custom prismatic joints
frequently predicted as revolute using `Ditto_s2m.ckpt`. For drawer-like objects, use
`Ditto_syn.ckpt` (trained on synthetic drawers). Never treat revolute output for a
prismatic-looking part as authoritative.

**pytorch-scatter ABI mismatch.** Must match the exact Torch + CUDA combo. Use the
dedicated wheel index; do not let pip build from source:
`pip install torch-scatter==2.0.9 -f https://data.pyg.org/whl/torch-1.10.2+cu113.html`

**pybullet 2.7.9 import failure on modern Linux.** OpenGL symbols missing in headless
containers. Install `libgl1-mesa-glx libglib2.0-0 libsm6 libxrender1` in the Docker image
even if no GUI is used.

**Hydra 1.1.0.rc1 config syntax.** All Ditto configs use pre-1.0 Hydra composition syntax
(`@hydra.main(config_path="configs/", config_name="config.yaml")`). Do not mix with
Hydra 1.2+ docs. Do not upgrade Hydra.

**No `scripts/predict.py`.** The released repo has no stand-alone predict CLI. The only
test entry point is `run_test.py` with Hydra overrides. The programmatic API via
`GeoArtModelV0` (see Workflow 1) is internal and unsupported.

**Box download scripts may break.** UT Austin Box redirects from `utexas.box.com` to
`utexas.app.box.com`, which breaks some headless download tools. Download checkpoints
manually, verify sha256, and cache in the container image. No GitHub Releases exist.

**Input format is preprocessed `.npz`, not `.ply`.** The released test loop reads
`<data_dir>/<data_path>/scenes/*.npz` with keys `pc_start`, `pc_end`, `seg_label_start`,
`screw_axis`, `joint_type`, etc. For custom point-cloud pairs, either write a matching
`.npz` file or use the programmatic API (Workflow 1) and build the normalized tensors
directly.

**Memory / `test_res` knob.** Default `test_res=32`. Lower to 16 for GPU memory pressure;
raise to 64 for higher-resolution mesh reconstruction (more memory). Override via:
`model.opt.hparams.test_res=16`.

**Axis sign ambiguity.** Commit `33276b6` patched sign handling. Compare both `+axis` and
`-axis` when checking agreement with the primary estimator; do not flag as disagreement on
sign alone.

## Advanced topics

**Install reference and Dockerfile**: `references/issues.md` — full PR #16 patch history,
exact conda YAML fields, and pybullet OS dependency list.

**Programmatic API internals**: `src/models/geo_art_model_v0.py` — `GeoArtModelV0` class,
`encode_inputs` / `decode_joints` call signature. Mirror `test_step` logic for exact
axis/pivot post-processing; the revolute/prismatic aggregation is non-trivial.

**Key config paths** (all require `experiment=Ditto_s2m` or `experiment=Ditto_syn`):
- `configs/experiment/Ditto_s2m.yaml` — Shape2Motion experiment
- `configs/experiment/Ditto_syn.yaml` — Synthetic experiment
- `configs/model/geo_art_model_v0.yaml` — `test_occ_th: 0.5`, `test_seg_th: 0.5`, `test_res: 32`
- `configs/trainer/minimal.yaml` — Lightning trainer fields (legacy 1.5 format)

**Custom `.npz` scene generation**: Reproduce `GeoArtDatasetV0` preprocessing — shared
bounding box normalization (`norm_padding: 0.1`), 8192 point sampling, occupancy query
generation. See `src/datamodules/datasets/geo_art_dataset_v0.py`.

**Sidecar confidence proxy** (not calibrated):
```python
p_prismatic = sigmoid(logits_joint_type).mean()        # over query points
confidence_proxy = max(p_prismatic, 1.0 - p_prismatic) # 0.5 = maximally uncertain
# In-distribution floor: 0.85; OOD floor: 0.90
```

## Resources

- Ditto repository: https://github.com/UT-Austin-RPL/Ditto
- License (MIT): https://github.com/UT-Austin-RPL/Ditto/blob/master/LICENSE
- Project page: https://ut-austin-rpl.github.io/Ditto/
- CVPR 2022 paper: https://arxiv.org/abs/2202.08227
- Pretrained Shape2Motion checkpoint (UT Austin Box): https://utexas.box.com/s/a4h001b3ciicrt3f71t4xd3wjsm04be7
- Pretrained synthetic checkpoint (UT Austin Box): https://utexas.box.com/s/zbf5bja20n2w6umryb1bcfbbcm3h2ysn
- Dataset (UT Austin Box): https://utexas.box.com/s/1wiynn7ql42c3mi1un7ynncfxr86ep22
- pytorch-scatter wheel index (torch-1.10.2+cu113): https://data.pyg.org/whl/torch-1.10.2+cu113.html
- PyTorch 1.10.2 previous-version install: https://pytorch.org/get-started/previous-versions/
- pytorch-lightning 1.5.4 docs: https://lightning.ai/docs/pytorch/1.5.4/
- nvidia/cuda 11.3.1 images: https://hub.docker.com/r/nvidia/cuda
- Open3D 0.12.0 release: https://github.com/isl-org/Open3D/releases/tag/v0.12.0
- Shape2Motion dataset: https://shape2motion.github.io/
- PartNet-Mobility (SAPIEN): https://sapien.ucsd.edu/browse
- hydra-core changelog: https://github.com/facebookresearch/hydra/releases
- GitHub issues #17 and #18 (install conflict, prismatic misclassification): https://github.com/UT-Austin-RPL/Ditto/issues
