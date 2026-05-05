# Validation Checklist (Reproduction Recipes)

Reproduction-level recipes for each gate family in [SKILL.md](../SKILL.md). The skill is the contract; this file gives an agent the concrete commands and Python snippets to compute the metrics from `twin_package/` artifacts.

## Capture gates

```
[ ] capture/capture_plan.yaml                          # required
[ ] capture/k_state_plan.yaml                          # required
[ ] capture/calibration/cameras.yaml                   # required
[ ] capture/calibration/scale_bars.json                # required
[ ] safety_photos/<state_id>.jpg                       # one per state
[ ] capture/logs/capture_session.jsonl                 # required
[ ] data hashes for raw images recorded                # ara/reproducibility/data_hashes.json
```

If any required artifact is missing, return to [multi-state-capture-protocol](../../multi-state-capture-protocol/SKILL.md).

## Pose gates

Read `reconstruction/poses/selected_pose_graph.json` (COLMAP/GLOMAP/hloc output). Compute:

- `registered_image_ratio = registered / planned`
- `mean_reproj_err_px = mean over images of mean track reprojection`
- `median_reproj_err_px`
- `mean_track_length`
- `scale_drift_pct = |estimated_scale - caliper_scale| / caliper_scale * 100`
- `sparse_points_per_registered = total_3d_points / registered_images`

Reference reproduction (pycolmap):

```python
import pycolmap
rec = pycolmap.Reconstruction("reconstruction/poses/colmap/0")
n_reg = len(rec.images)
mean_reproj = sum(img.mean_reprojection_error for img in rec.images.values()) / n_reg
```

Cross-check scale via AprilTag-pair detections and caliper measurements from `measurements.csv`.

## Rendering gates (3DGS)

Held-out frames (10–15% stratified by state/view) live in `validation/regression_snapshots/heldout_renders/<state_id>/*.png`. Compute PSNR/SSIM/LPIPS per held-out frame; aggregate per-state and global.

```python
import torch, lpips
from torchmetrics.image import PeakSignalNoiseRatio, StructuralSimilarityIndexMeasure
psnr = PeakSignalNoiseRatio(data_range=1.0)
ssim = StructuralSimilarityIndexMeasure(data_range=1.0)
lp = lpips.LPIPS(net='vgg')
# render_pred and render_gt are (1, 3, H, W) in [0,1]
psnr_val = psnr(render_pred, render_gt).item()
ssim_val = ssim(render_pred, render_gt).item()
lp_val = lp(render_pred, render_gt).item()
```

Per-control-label ROI: extract the bounding box of each labeled control from `semantics/labels/controls.yaml` and run PSNR on cropped regions.

If LPIPS >0.18 with PSNR ≥28: switch to [training-reflection-aware-splats](../../../23-3d-reconstruction/training-reflection-aware-splats/SKILL.md).

## Surface gates (Chamfer per part class)

Read `reconstruction/surfaces/meshes_repaired/<segment_id>.obj` and compare against caliper-measured ground truth or CAD when available. Use Open3D:

```python
import open3d as o3d
mesh = o3d.io.read_triangle_mesh("reconstruction/surfaces/meshes_repaired/seg_042.obj")
ref  = o3d.io.read_triangle_mesh("ground_truth/seg_042_caliper_ref.obj")
pcd_pred = mesh.sample_points_uniformly(number_of_points=100000)
pcd_ref  = ref.sample_points_uniformly(number_of_points=100000)
d_pred_to_ref = pcd_pred.compute_point_cloud_distance(pcd_ref)
median = float(np.median(d_pred_to_ref))
p95    = float(np.percentile(d_pred_to_ref, 95))
```

Watertight check: every collision mesh must satisfy `mesh.is_watertight() and mesh.is_edge_manifold(allow_boundary_edges=False) and mesh.is_vertex_manifold()`. If not, route to [conditioning-collision-meshes](../../../27-physics-simulation/conditioning-collision-meshes/SKILL.md).

## Segmentation gates

Read `semantics/3d_masks/` and `semantics/gaussian_groups/`. Compute:

- foreground assignment rate = (assigned Gaussians) / (total non-background Gaussians)
- semantic mIoU vs human-labeled ground-truth subset
- segment point counts per part

If mIoU <0.75: route to [per-gaussian-saga](../../../24-3d-segmentation-articulation/per-gaussian-saga/SKILL.md) for promptable correction.

## Affordance gates (VLM)

Read `semantics/affordances.json`. Validate:

```python
import json, jsonschema
schema = json.load(open("validation/schemas/affordances.schema.json"))
data   = json.load(open("semantics/affordances.json"))
jsonschema.validate(data, schema)
```

Then enforce:

- 100% of items have `evidence.image_ids` and `evidence.state_ids` non-empty.
- 100% of items have `segment_id` that exists in `semantics/3d_masks/`.
- 100% of `safety_level: safety-critical` items have `human_review.signed_at` set.
- Cross-model disagreement: when running ≥2 VLMs, compare `affordance_type`, `safety_level`, `bbox_3d` IoU, and `confidence` spread.

Failure routes to [vlm-physics-validation-loop](../../../25-affordance-vlm/vlm-physics-validation-loop/SKILL.md).

## Articulation gates

Read `articulation/joint_hypotheses.json`. For each joint:

- Revolute axis angular error = angle(estimated_axis, ground_truth_axis_from_CAD_or_manual).
- Prismatic axis angular error.
- Joint origin error = ||estimated_origin - ground_truth_origin||.
- Held-out keypoint RMS = RMS over held-out state's keypoints predicted by joint model vs measured.
- K_states_used must be ≥4 for `ship_ready: true`.

If axis error >3° (revolute) or >2° (prismatic): refit with state-correspondence cleanup via [multistate-diff-open3d](../../../24-3d-segmentation-articulation/multistate-diff-open3d/SKILL.md), then route to [articulation-ditto-prior](../../../24-3d-segmentation-articulation/articulation-ditto-prior/SKILL.md) or [screwsplat-articulation](../../../24-3d-segmentation-articulation/screwsplat-articulation/SKILL.md).

## Physics gates

For each backend (URDF, MJCF, USD):

```python
# URDF load (PyBullet)
import pybullet as p
p.connect(p.DIRECT)
robot = p.loadURDF("articulation/urdf/equipment.urdf")
# verify joints
n_j = p.getNumJoints(robot)
for j in range(n_j):
    info = p.getJointInfo(robot, j)
    assert info[2] in (p.JOINT_REVOLUTE, p.JOINT_PRISMATIC, p.JOINT_FIXED)
```

```python
# MJCF load (MuJoCo)
import mujoco
m = mujoco.MjModel.from_xml_path("articulation/mjcf/equipment.xml")
d = mujoco.MjData(m)
mujoco.mj_step(m, d)  # one step shouldn't NaN
```

Resting drift: simulate 10 s with no input forces, measure RMS pose change for each link.

Cross-engine endpoint disagreement: drive joint to fixed target (e.g. chamber door at 90°) in MuJoCo and Isaac Lab; compare end-effector position. >5 mm → reconcile coordinate frames in [authoring-urdf-mjcf-usd](../../../27-physics-simulation/authoring-urdf-mjcf-usd/SKILL.md).

## VR gates

For Quest 3: deploy via [deploying-quest-spatial-splats](../../../26-3d-rendering-vr/deploying-quest-spatial-splats/SKILL.md), profile with Meta XR Performance HUD, capture FPS and motion-to-photon over a 60 s scripted walk-through.

For Vision Pro: deploy via [rendering-unity-splats](../../../26-3d-rendering-vr/rendering-unity-splats/SKILL.md), profile with Unity Profiler over a scripted walk; FPS ≥90 sustained, no frame drops below 80.

Visible triangle budget: for Quest 3, target <1.5M triangles in any single frustum; for Vision Pro / desktop, 2–5M depending on shader complexity.

## Regression diff

Compare current `regression_snapshots/` against the prior tagged release:

- PSNR delta per held-out frame (alarm if >0.5 dB worse without explanation)
- Mesh slice diff (visualize as overlaid contours)
- Joint axis delta (alarm if >0.5° drift between PATCH releases without changelog entry)

Block release if regression diff is unexplained.

## Final certification stamp

When ALL required gates green AND human reviews signed AND regression diff explained:

```json
{
  "status": "validated",
  "stamp": {
    "validator": "validating-digital-twins/SKILL.md",
    "skill_version": "1.0.0",
    "timestamp": "2026-05-04T12:00:00Z",
    "git_commit": "abc1234",
    "container_digest": "sha256:..."
  }
}
```

Hand off to [versioning-twins-with-ara](../../versioning-twins-with-ara/SKILL.md).
