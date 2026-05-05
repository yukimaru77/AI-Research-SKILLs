# Ditto — GitHub Issues, PRs, and Install Workarounds

Source: UT-Austin-RPL/Ditto GitHub issue/PR history, verified May 2026.

---

## GitHub Issue and PR History

| ID | Date | Status | Summary |
|----|------|--------|---------|
| PR #16 | 2024-12-20 | Merged | Updated `conda_env_gpu.yaml` to `pip<24.1`; changed `pykdtree` to `1.3.0`. Commits: `b34b45f60b4d667db3297a45c6556783c6077546` (env update), `b5833a627afebe9f3359893dc7c88f32737a530d` (requirements update). Last meaningful upstream activity. |
| PR #15 | 2024-12-20 | Closed | Precursor dependency patch around `pykdtree`; superseded by PR #16. |
| Issue #18 | 2025-04-27 | Open | **Critical for lab use.** Custom prismatic joints predicted as revolute using `Ditto_s2m.ckpt`. User-confirmed failure mode on custom data outside training distribution. For drawer-like objects, prefer `Ditto_syn.ckpt`. Never treat revolute output for a known prismatic part as authoritative. |
| Issue #17 | 2025-04-16 | Open | **Install blocker.** `numpy==1.9.5` pin in `requirements.txt` conflicts with PyTorch Lightning's numpy dependency. Fix: patch pin to `numpy==1.21.6` before installing. NumPy 1.21.6 is the last 1.x release with clean Python 3.8 support. |
| Issue #12 | 2023-04-18 | Open | Dataset generation question. Relevant if building custom `.npz` scene files. See `src/datamodules/datasets/geo_art_dataset_v0.py` for the preprocessing schema. |
| Issue #6 | 2022-05-19 | Open | File-not-found on data layout. Relevant only if reproducing original Shape2Motion data tree exactly. |

**Not found in upstream issues (as of May 2026):**
- Ampere-specific or Ada Lovelace-specific `pytorch-scatter` CUDA kernel failures.
- Checkpoint incompatibility between torch 1.10.x and newer torch versions.
- Lightning 1.6.x-specific Ditto failure reports.
- OOM issues on smaller GPUs.
- A maintained community fork that modernizes install + inference.

---

## Install: Exact Dependency Pins

Repo-confirmed environment from `conda_env_gpu.yaml` (post PR #16) and `requirements.txt`:

```
python=3.8
pip<24.1
cudatoolkit=11.3
pytorch=1.10.2=py3.8_cuda11.3_cudnn8.2.0_0
torchvision
pytorch-scatter

pytorch-lightning==1.5.4
torchmetrics==0.4.1
setuptools==59.5.0
hydra-core==1.1.0.rc1
hydra-colorlog==1.1.0.dev1
hydra-optuna-sweeper==1.1.0.dev2
open3d==0.12.0
pybullet==2.7.9
numpy==1.9.5   ← PATCH TO 1.21.6 (issue #17)
pykdtree==1.3.0
```

**Python version matrix:**

| Python | Status |
|--------|--------|
| 3.8 | Confirmed upstream target; use this. |
| 3.7 | Not repo-confirmed; `conda_env_gpu.yaml` does not target py3.7. |
| 3.9 | Not recommended; Open3D 0.12.0 Linux wheels cover 3.6–3.8 only. |

---

## Install Recipe (2025/2026 Patched)

```bash
git clone https://github.com/UT-Austin-RPL/Ditto.git
cd Ditto

# Patch ancient NumPy pin (issue #17)
sed -i 's/numpy==1.9.5/numpy==1.21.6/' requirements.txt

conda create -n Ditto-py38 python=3.8 "pip<24.1" -y
conda activate Ditto-py38

conda install -y -c pytorch -c conda-forge -c pyg \
  cudatoolkit=11.3 \
  pytorch=1.10.2 \
  torchvision \
  pytorch-scatter

pip install -r requirements.txt
python scripts/convonet_setup.py build_ext --inplace
```

`pytorch-scatter` wheel (pip fallback, cp38):
```bash
pip install torch-scatter==2.0.9 \
  -f https://data.pyg.org/whl/torch-1.10.2+cu113.html
```

Direct cp38 wheel URL:
```
https://data.pyg.org/whl/torch-1.10.2%2Bcu113/torch_scatter-2.0.9-cp38-cp38-linux_x86_64.whl
```

---

## Dockerfile (Minimal Working Base)

```dockerfile
FROM nvidia/cuda:11.3.1-cudnn8-devel-ubuntu20.04
# Use cudnn8 variant — Ditto's PyTorch build is CUDA 11.3 + cuDNN 8.2.

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y \
    build-essential git wget bzip2 ca-certificates \
    libgl1-mesa-glx libglib2.0-0 libx11-6 libxext6 libsm6 libxrender1 \
    && rm -rf /var/lib/apt/lists/*

# Install Miniconda with Python 3.8
RUN wget -q https://repo.anaconda.com/miniconda/Miniconda3-py38_23.3.1-0-Linux-x86_64.sh \
    -O /tmp/miniconda.sh && \
    bash /tmp/miniconda.sh -b -p /opt/conda && rm /tmp/miniconda.sh
ENV PATH=/opt/conda/bin:$PATH

# Clone and install Ditto
RUN git clone https://github.com/UT-Austin-RPL/Ditto.git /opt/Ditto
WORKDIR /opt/Ditto
RUN sed -i 's/numpy==1.9.5/numpy==1.21.6/' requirements.txt

RUN conda create -n Ditto-py38 python=3.8 "pip<24.1" -y && \
    conda run -n Ditto-py38 conda install -y -c pytorch -c conda-forge \
      cudatoolkit=11.3 pytorch=1.10.2 torchvision && \
    conda run -n Ditto-py38 pip install torch-scatter==2.0.9 \
      -f https://data.pyg.org/whl/torch-1.10.2+cu113.html && \
    conda run -n Ditto-py38 pip install -r requirements.txt && \
    conda run -n Ditto-py38 python scripts/convonet_setup.py build_ext --inplace

# Checkpoint download is manual — Box links may not work in headless wget.
# Copy pre-downloaded checkpoints at build time:
# COPY Ditto_s2m.ckpt /opt/Ditto/pretrained/
# COPY Ditto_syn.ckpt /opt/Ditto/pretrained/
```

---

## Pretrained Checkpoints

| File | Box URL | Notes |
|------|---------|-------|
| `Ditto_s2m.ckpt` | `https://utexas.box.com/s/a4h001b3ciicrt3f71t4xd3wjsm04be7` | Shape2Motion-trained. Filename confirmed by issue #18 report. |
| `Ditto_syn.ckpt` | `https://utexas.box.com/s/zbf5bja20n2w6umryb1bcfbbcm3h2ysn` | Synthetic-trained. Filename inferred from experiment config naming; verify after download. |
| Dataset | `https://utexas.box.com/s/1wiynn7ql42c3mi1un7ynncfxr86ep22` | Full Shape2Motion + synthetic data. |

Box redirects from `utexas.box.com` to `utexas.app.box.com` — headless download scripts
(wget, curl without cookies) may fail. Download manually in a browser, then COPY into the
container. Store sha256 checksums for reproducibility. No GitHub Releases exist.

---

## Key Config Files

```
configs/experiment/Ditto_s2m.yaml      # Shape2Motion experiment
configs/experiment/Ditto_syn.yaml      # Synthetic experiment
configs/datamodule/default_datamodule.yaml
configs/model/geo_art_model_v0.yaml    # test_occ_th, test_seg_th, test_res knobs
configs/model/network/geo_art_net_v0.yaml  # ConvONets c_dim=64, PointNet++-style encoder
configs/trainer/minimal.yaml           # Lightning 1.5 trainer fields
run.py                                  # training entry
run_test.py                             # test/inference entry
src/models/geo_art_model_v0.py         # GeoArtModelV0 Lightning module
src/datamodules/datasets/geo_art_dataset_v0.py  # npz loading, normalization
src/models/modules/__init__.py         # create_network factory
```

Always pass `experiment=Ditto_s2m` or `experiment=Ditto_syn` — the base `config.yaml`
alone does not resolve cleanly to a runnable GeoArt configuration.

---

## Output Schema (`quant.npz`)

Primary machine-readable output from `run_test.py`:

| Field | Type | Notes |
|-------|------|-------|
| `joint_type` | int | 0 = revolute, 1 = prismatic |
| `joint_axis` | (3,) float | Predicted axis direction (normalized) |
| `pivot_point` | (3,) float | Pivot point in normalized space |
| `config` | float | Joint configuration value |

Mesh outputs: `static.obj`, `mobile.obj`, `bounding_box.json`, `out.urdf`.

**No calibrated confidence score is written by default.** Proxy only:
```python
p_prismatic = sigmoid(logits_joint_type).mean()
confidence_proxy = max(p_prismatic, 1.0 - p_prismatic)
```

Per-point logits/labels are not saved unless `test_step` is patched.

---

## Relevant Fix: Axis Sign Ambiguity

Commit `33276b6` fixed joint estimation for ambiguous axis direction. The patch compares
predicted axis and its negative, then adjusts configuration sign for revolute/prismatic
evaluation. For sidecar use: always compare both `+axis` and `-axis` against the primary
estimator before flagging disagreement.
