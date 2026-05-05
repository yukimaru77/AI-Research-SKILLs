# Articulation Priors Issues and Tested Versions

## Dataset access matrix

| Source                       | Access                                              | License       | Last verified |
|------------------------------|-----------------------------------------------------|---------------|---------------|
| PartNet-Mobility             | Registration + ToS at https://sapien.ucsd.edu/      | Asset terms   | 2025          |
| SAPIEN code                  | https://github.com/haosulab/SAPIEN                  | Apache-2.0    | 2025          |
| OPDMulti                     | https://github.com/3dlg-hcvc/OPDMulti               | MIT           | 2024          |
| OPDFormer                    | https://github.com/3dlg-hcvc/OPDFormer              | MIT           | 2024          |
| GAPartNet                    | https://github.com/PKU-EPIC/GAPartNet               | CC BY-NC 4.0  | 2024          |
| AKB-48                       | https://github.com/liuliu66/AKB-48 + project page   | Project ToS   | 2024          |
| 3DAffordanceNet              | https://github.com/pearl-robot-lab/3DAffordanceNet  | MIT           | 2023          |
| PartObjaverse-Tiny / SAMPart3D | https://github.com/Pointcept/SAMPart3D            | MIT code; CC BY-NC 4.0 dataset | 2024 |
| AffordanceLLM                | https://github.com/JasonQSY/AffordanceLLM           | No license file | 2024        |

## SAPIEN Vulkan / EGL

SAPIEN offscreen rendering requires Vulkan ICD inside the container.

```bash
docker run --rm --gpus all \
  -e NVIDIA_DRIVER_CAPABILITIES=compute,utility,graphics \
  -e VK_ICD_FILENAMES=/usr/share/vulkan/icd.d/nvidia_icd.json \
  -v "$PWD":/workspace -w /workspace \
  sapien:cu124 python load_partnet_mobility.py
```

Common errors:

- `cannot create Vulkan instance` => install NVIDIA Vulkan ICD in container.
- `no Vulkan ICD found` => set `VK_ICD_FILENAMES` to the ICD JSON path.
- `Vulkan device with compute/graphics queues not found` => verify `graphics` in driver capabilities.

## OPDMulti / OPDFormer legacy stack

Tested:

```bash
conda create -n opdmulti python=3.7 -y
conda activate opdmulti
conda install pytorch==1.10.1 cudatoolkit=11.1 -c pytorch -c nvidia -y
pip install -e .
```

Keep this env SEPARATE from the main vLLM CUDA 12.8 image. Call OPDMulti as a subprocess; serialize predictions through JSON.

## 3DAffordanceNet legacy stack

Tested:

```bash
conda create -n affordancenet python=3.7 -y
conda activate affordancenet
pip install torch==1.0.1 torchvision==0.2.2
```

Or just port the affordance taxonomy (no need to run the model) into your VLM prompt vocabulary. The taxonomy is the actually useful asset.

## GAPartNet license

CC BY-NC 4.0. Treat as non-commercial. Use for academic evaluation; do NOT bundle weights into a commercial pipeline. The taxonomy (handle, lever, lid, door, button, drawer) can be referenced as a vocabulary without redistributing the dataset.

## PartNet-Mobility orientation drift

Many PartNet-Mobility entries assume Y-up while lab pipelines often use Z-up. Always normalize object frames before scoring; record original `T_object_world`. Articulate-Anything notes mention orientation/grounding issues for the same dataset.

## AKB-48 dataset URLs unstable

GitHub repo is sparse; the actual data is on the project homepage. Mirror to a stable internal URL. Record dataset version. Do not assume URLs persist.

## Source weighting for prior aggregation

```python
SOURCE_WEIGHTS = {
    "partnet_mobility": 1.0,    # canonical revolute/prismatic priors
    "opdmulti": 0.9,             # direct evaluator with motion type/axis/origin
    "gapartnet": 0.7,            # actionable-part taxonomy; non-commercial
    "akb48": 0.5,                # real-world articulated objects; URLs unstable
    "3daffordancenet": 0.3,      # affordance verbs only, no axis/range
}
```

## SEM-specific defaults

Recommended prior rules for SEM/lab equipment when retrieved priors agree:

- Knob / rotary valve / handwheel: revolute; axis along visible shaft or normal to circular face; anchor at shaft/knob center; range `[-pi, pi]` continuous OR stop-limited `[0, pi/2]`/`[0, pi]`.
- Linear stage / drawer / specimen stage: prismatic; axis along rails / dovetails / screw shafts; range = rail_length - carriage_length (NOT VLM-guessed).
- Hinged cover / load-lock door / chamber hatch: revolute; axis through hinge barrels or hinge pin line; anchor on hinge line; range starts at 0 closed; clip by collisions.
- Ports / flanges / screws / clamps / detector housings / fixed brackets: fixed unless clear motion evidence.

## Geometric snapping

- Hinge axis: PCA on hinge-barrel point set; sign canonical.
- Rail axis: PCA on rail-edge point set; carriage centroid projected onto axis.
- Cylinder axis: PCA on shaft point set; axis = principal direction.

```python
def fit_axis_pca(points, k=20):
    if len(points) < k: raise ValueError(f"need >= {k} points")
    centered = points - points.mean(axis=0)
    _, _, vh = np.linalg.svd(centered, full_matrices=False)
    return vh[0] / np.linalg.norm(vh[0])
```

## License redistribution checklist

Before any external release of derived datasets:

- [ ] PartNet-Mobility: cite paper; respect asset access ToS; do NOT redistribute raw assets.
- [ ] GAPartNet: CC BY-NC 4.0; non-commercial only.
- [ ] AKB-48: project terms; verify before commercial use.
- [ ] PartObjaverse-Tiny: dataset CC BY-NC 4.0.
- [ ] 3DAffordanceNet: MIT code; dataset terms vary.
- [ ] AffordanceLLM: no license file; treat conservatively, do not redistribute.
