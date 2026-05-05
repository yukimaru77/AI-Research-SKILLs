# gsplat_joint_spine module reference

The reusable agent-facing implementation lives in a single file `gsplat_joint_spine.py`. This reference documents the public API and the algorithmic shape of each function. The full implementation is sourced from the Phase A Deep_thinker analysis and validated against Open3D 0.19.0 + pytransform3d 3.15.0.

## Top-level entry points

### `compare_two_states(*, state0_path, state1_path, part_id, unit_scale, voxel_size, diff_eps, stable_eps, min_cluster_size, diff_mode, occupancy_voxel, min_translation) -> dict`

The main agent-facing function. Input: two PLY paths (Gaussian centers). Output: a JSON-able dict with `joint_type`, `axis_direction`, `axis_point`, `transform_0_to_1`, `theta_rad`, `theta_deg`, `translation_magnitude`, `pitch`, `residuals`, `confidence`, `diagnostics`.

Pipeline (each step a separate function below):
1. `load_gaussian_centers_ply(state0_path)` and `load_gaussian_centers_ply(state1_path)`.
2. Voxel downsample both at `voxel_size` for speed.
3. `align_scenes_with_stable_voting()` -> scene transform `T_scene_1_to_0`.
4. Apply scene transform to state1 -> `state1_aligned`.
5. `extract_changed_candidates()` -> `(old_candidates, new_candidates)`.
6. `largest_hdbscan_cluster()` on each candidate set.
7. `fit_part_transform(old_cluster, new_cluster)` -> rigid SE(3).
8. `classify_joint_transform()` -> joint_type, axis, pitch, confidence.

### `aggregate_axis_observations(results) -> dict`

For 3-state cases (e.g. focus knob at 0/30/60 deg): take a list of revolute/screw joint records and aggregate axis_direction (eigenvector of weighted outer product) and axis_point (least-squares closest point to all observed 3D lines). Returns confidence weighted by angle consistency, support, and base confidences.

### `ransac_line_3d(points, *, threshold, iterations=256, rng_seed=0) -> dict`

Generic RANSAC line fitter. Useful for fitting hinge-edge points or repeated axis-point estimates.

## Loading and preprocessing

### `load_gaussian_centers_ply(path, *, unit_scale=1.0, voxel_size=None) -> open3d.geometry.PointCloud`

Reads PLY with Open3D (vertex `x, y, z`); falls back to trimesh if Open3D returns an empty cloud. Multiplies coordinates by `unit_scale` (1.0 for meters, 0.001 for mm). Filters non-finite rows. Optionally voxel-downsamples.

Opacity / scale / rotation attributes are ignored. For production filtering of low-opacity floaters, use `gsplat-scene-adapter` upstream.

### `make_pcd(points)`, `points_of(pcd)`, `transform_copy(pcd, T)`, `bbox_diag(points)`

Thin Open3D helpers.

## Scene alignment

### `preprocess_for_fpfh(pcd, voxel_size) -> (down, fpfh)`

Voxel downsample, estimate normals (radius `2.5 * voxel_size`, `max_nn=30`), compute FPFH features (radius `5 * voxel_size`, `max_nn=100`).

### `register_ransac_then_icp(source, target, *, voxel_size, init=None, use_global=True, max_icp_iter=80) -> (T, diag)`

RANSAC+FPFH coarse alignment (`distance_threshold = 1.5 * voxel_size`, `RANSACConvergenceCriteria(100_000, 0.999)`, `CorrespondenceCheckerBasedOnEdgeLength(0.9)`, `CorrespondenceCheckerBasedOnDistance`), then point-to-point ICP (`icp_threshold = 3 * voxel_size`).

Returns 4x4 transform plus diagnostic dict with `global_fitness`, `global_inlier_rmse`, `icp_fitness`, `icp_inlier_rmse`.

### `align_scenes_with_stable_voting(state0, state1, *, voxel_size, stable_eps) -> (T, diag)`

Two-pass alignment. First pass: align all of state1 to state0. Second pass: vote points whose NN distance to state0 is below `stable_eps` as "stable", re-run ICP on the stable subset only. This prevents the moved part (which can be a large fraction of the scene, e.g. cabinet door) from corrupting alignment.

Falls back to the first-pass transform if fewer than `max(100, 0.05 * len(state1.points))` stable points are found.

## Differencing

### `nn_distances(source, target) -> np.ndarray`

Wraps `pcd.compute_point_cloud_distance(target)` to return per-point nearest-neighbor distances.

### `voxel_keys(points, voxel)`, `occupancy_difference_mask(source_points, target_points, *, voxel, neighbor_radius=1)`

Voxel-hash occupancy comparison. For each source point, check whether its (3x3x3) voxel neighborhood is occupied in the target point set. More robust than pure NN distance when point density differs between the two scenes.

### `extract_changed_candidates(state0, state1_aligned_to_0, *, diff_eps, diff_mode, occupancy_voxel) -> (old_candidates, new_candidates, diag)`

Two modes:
- `diff_mode="distance"`: `mask_old = nn_distances(state0, state1_aligned) > diff_eps`, symmetric for new.
- `diff_mode="occupancy"`: `mask_old = occupancy_difference_mask(state0, state1_aligned, voxel=occupancy_voxel)`, symmetric for new.

`distance` is the default; switch to `occupancy` for large displacements (cabinet doors) where NN distances saturate.

## Clustering

### `largest_hdbscan_cluster(pcd, *, min_cluster_size, min_samples=None) -> (pcd, diag)`

Runs `sklearn.cluster.HDBSCAN` on the candidate point set, picks the largest non-noise cluster. Falls back gracefully when HDBSCAN labels everything as noise.

For multi-cluster scenes, replace this with a loop over all valid labels and emit one part per cluster.

## Rigid transform fit

### `fit_part_transform(old_cluster_state0, new_cluster_state1_in_0, *, voxel_size) -> (T_part, diag)`

Initialize with the centroid translation `pts_new.mean - pts_old.mean`. Voxel-downsample. Run RANSAC+FPFH then ICP. Compute symmetric NN residuals for the diagnostic block.

### `symmetric_nn_residual(source, target, T) -> dict`

Computes `symmetric_nn_rmse`, `symmetric_nn_median`, `symmetric_nn_p90` of distances between transformed source and target, both directions.

## Screw decomposition

### `decompose_screw(T) -> dict`

```python
import pytransform3d.transformations as pt
Stheta = pt.exponential_coordinates_from_transform(T)
rotvec, vtheta = Stheta[:3], Stheta[3:]
theta = np.linalg.norm(rotvec)

dq = pt.dual_quaternion_from_transform(T)
q, s_axis, h, theta = pt.screw_parameters_from_dual_quaternion(dq)
```

`q` is a point on the screw axis, `s_axis` is the direction, `h` is pitch, `theta` is the transform parameter. Sign of `s_axis` is aligned with the SO(3) log to be consistent across observations.

## Classification

### `classify_joint_transform(T, *, old_cluster, new_cluster, residuals, diff_eps, angle_small_deg=5.0, min_translation=None, pitch_eps=None, min_cluster_size=80) -> dict`

Decision rules:
- `prismatic`: `theta < 5 deg AND translation_magnitude >= max(3*diff_eps, 3*rmse, 0.01*scale)`.
- `revolute`: `theta >= 5 deg AND |pitch| <= max(3*diff_eps, 0.02*scale)`.
- `screw`: `theta >= 5 deg AND axial_motion = |pitch * theta| >= translation_threshold`.
- `ambiguous`: weak cluster (`moved_support < max(10, min_cluster_size//2)`) OR high residual (`rmse > max(5*diff_eps, 0.08*scale)`) OR small motion (both `theta < 1 deg` and small translation).

Confidence:
```python
residual_score = exp(-rmse / (2*diff_eps))
support_score  = min(1, moved_support / min_cluster_size)
motion_score   = min(1, max(theta / angle_small_rad, translation_magnitude / translation_threshold))
confidence = residual_score * support_score * motion_score
```

If `joint_type == "ambiguous"`, multiply confidence by 0.25.

## CLI

```bash
python gsplat_joint_spine.py state0.ply state1.ply \
  --part-id moving_cluster_0 \
  --unit-scale 0.001 \
  --voxel 0.002 \
  --diff-eps 0.006 \
  --stable-eps 0.012 \
  --min-cluster-size 80 \
  --diff-mode distance \
  --occupancy-voxel 0.006 \
  --min-translation 0.002
```
