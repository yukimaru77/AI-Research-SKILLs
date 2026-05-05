---
name: conditioning-collision-meshes
description: Converts raw 3DGS-derived visual meshes into physics-engine-ready collision geometry for MuJoCo 3.x, Isaac Sim/Lab 4.x+, SAPIEN 3.x, and Genesis. Performs watertighting, simplification, manifold repair, and convex decomposition (CoACD primary, V-HACD archived). Outputs named convex STL parts, MJCF/URDF asset snippets, and audit logs. Use when segmented lab-equipment meshes (SEM shells, optical bench knobs, sample stages) must drive rigid-body contact, collision, and inertia in a physics engine.
version: 2.0.0
author: Orchestra Research
license: MIT
tags: [Physics Simulation, Mesh Repair, Collision, Convex Decomposition, CoACD, MuJoCo, Isaac Sim, SAPIEN, Genesis]
dependencies: [trimesh==4.12.2, coacd==1.0.10, libigl==2.6.2, manifold3d==3.4.1, pymeshlab==2025.7.post1, pytetwild==0.2.3, usd-core==26.5, numpy>=1.26, scipy>=1.11]
---

# conditioning-collision-meshes

## Quick start

Pinned stack (verified against PyPI / GitHub releases as of May 2026):

| Package | Version | Release date | License |
|---|---|---|---|
| trimesh | 4.12.2 | 2026-05-01 | MIT |
| coacd | 1.0.10 | 2026-04-10 | MIT |
| libigl | 2.6.2 | 2026-03-05 | MPL-2.0 |
| manifold3d | 3.4.1 | 2026-03-24 | Apache-2.0 |
| pymeshlab | 2025.7.post1 | 2026-01-30 | GPL-3.0 |
| pytetwild | 0.2.3 | 2026-02-04 | MPL-2.0 |
| usd-core | 26.5 | 2026-04-24 | TOST-1.0 |
| open3d | 0.19.0 | 2025-01-08 | MIT |

**V-HACD is archived/EOL.** Upstream explicitly redirects to CoACD for new development. Do not introduce V-HACD in new pipelines.

**ManifoldPlus license is non-commercial only** — cannot be used in this pipeline without separate legal clearance. Use `manifold3d` (Apache-2.0) instead.

PyMeshLab is GPL-3.0: isolate it in a subprocess venv to keep the main pipeline MIT/Apache-clean.

```bash
python3.11 -m venv .venv-collision
source .venv-collision/bin/activate
pip install --upgrade pip wheel setuptools
pip install "trimesh==4.12.2" "coacd==1.0.10" "libigl==2.6.2" \
  "manifold3d==3.4.1" "pytetwild==0.2.3" "usd-core==26.5" \
  "numpy>=1.26" "scipy>=1.11"

# GPL isolation for PyMeshLab repair pass
python3.11 -m venv .venv-pymeshlab-gpl
.venv-pymeshlab-gpl/bin/pip install "pymeshlab==2025.7.post1"
```

### Engine collision rules

- **MuJoCo 3.x**: Non-convex mesh geoms are internally replaced by their convex hull for collision. Always output a *union of named convex geoms*, not a single visual mesh.
- **Isaac Sim/Lab 4.x+**: Exposes Convex Decomposition, Convex Hull, Triangle Mesh, SDF Mesh. Triangle Mesh and Mesh Simplification are unsupported for rigid bodies and fall back to convex hull. Use contact/rest offsets for thin panels.
- **SAPIEN 3.x** (3.0.3, 2026-03-10, MIT): `actor_builder.add_multiple_collisions_from_file()` converts connected components to convex shapes; non-convex shapes are limited to static/kinematic.
- **Genesis** (0.4.6, 2026-04-11): Meshes are decimated and convexified by default. Pass `decimate=False, convexify=False` when your pipeline pre-computes named hulls.

## Common workflows

### 1. Thin-shell SEM enclosure — convex decomposition

```
Task Progress:
- [ ] Step 1: Load visual SEM enclosure segment; concatenate scene if multi-body
- [ ] Step 2: Normalize units to meters (auto-detect mm)
- [ ] Step 3: Remove degenerate/duplicate faces; fix normals; fill holes with trimesh
- [ ] Step 4: Validate edge + vertex manifoldness with libigl
- [ ] Step 5: If non-watertight after trimesh repair, run manifold3d manifold() operation
- [ ] Step 6: Run CoACD (threshold 0.02–0.04; more parts = tighter approximation)
- [ ] Step 7: Verify every output hull is convex and manifold
- [ ] Step 8: Export named STL parts; emit MJCF <mesh>/<geom> snippets
- [ ] Step 9: Record part count, volume error, max-convexity violation in audit.json
```

SEM enclosures are thin shells. Do not trust a shell's near-zero volume for inertia — use a solid proxy geometry, manufacturer mass, or a convexified watertight volume for `<inertial>`. Chamber doors and viewports may push the threshold high enough to merge; test with `threshold=0.04` first and tighten only if the door/viewport disappears.

```python
from pathlib import Path
import numpy as np
import trimesh, coacd
import importlib.metadata  # libigl no longer exposes __version__; use this

# Verify libigl version without AttributeError
libigl_ver = importlib.metadata.version("libigl")  # e.g. "2.6.2"

import igl

def load_repair(path: Path) -> trimesh.Trimesh:
    m = trimesh.load(str(path), force="mesh")
    if isinstance(m, trimesh.Scene):
        m = trimesh.util.concatenate(tuple(m.geometry.values()))
    m.process(validate=True)
    m.update_faces(m.unique_faces())
    m.update_faces(m.nondegenerate_faces())
    m.remove_unreferenced_vertices()
    m.merge_vertices()
    trimesh.repair.fill_holes(m)
    trimesh.repair.fix_normals(m)
    return m

def meters_from_auto_units(m: trimesh.Trimesh, expected_max_m: float = 0.6) -> trimesh.Trimesh:
    max_ext = float(np.max(m.extents))
    if max_ext > 1.0 and (max_ext / 1000.0) <= expected_max_m * 5:
        m.apply_scale(0.001)
    return m

mesh = load_repair(Path("sem_enclosure_visual.stl"))
mesh = meters_from_auto_units(mesh, expected_max_m=0.6)

V = np.asarray(mesh.vertices, dtype=np.float64)
F = np.asarray(mesh.faces,    dtype=np.int64)
assert bool(igl.is_edge_manifold(F)), "non-manifold edges — run manifold3d pass first"

if not mesh.is_watertight:
    # manifold3d guaranteed-manifold repair (Apache-2.0, safe license)
    import manifold3d as mf
    man = mf.Manifold(mf.Mesh(vert_properties=V.astype(np.float32),
                               tri_verts=F.astype(np.uint32)))
    out = man.to_mesh()
    V = out.vert_properties.astype(np.float64)
    F = out.tri_verts.astype(np.int64)
    mesh = trimesh.Trimesh(vertices=V, faces=F, process=True)
    assert mesh.is_watertight, "manifold3d repair failed"

cm    = coacd.Mesh(V, F)
parts = coacd.run_coacd(cm, threshold=0.03, mcts_iterations=200,
                         preprocess_mode="auto", max_convex_hull=96, seed=7)

OUT = Path("mjcf_sem_collision"); OUT.mkdir(exist_ok=True)
asset_lines = ["<asset>"]
geom_lines  = ['<body name="sem_enclosure_collision">']
for i, (v, f) in enumerate(parts):
    part = trimesh.Trimesh(v, f, process=True); part.fix_normals()
    name = f"sem_col_{i:03d}"
    fpath = OUT / f"{name}.stl"; part.export(str(fpath))
    asset_lines.append(f'  <mesh name="{name}" file="{fpath.as_posix()}"/>')
    geom_lines.append(
        f'  <geom type="mesh" mesh="{name}" contype="1" conaffinity="1" '
        f'margin="0.001" solref="0.02 1"/>')
asset_lines.append("</asset>"); geom_lines.append("</body>")
(OUT / "sem_assets.xml").write_text("\n".join(asset_lines) + "\n")
(OUT / "sem_geoms.xml").write_text("\n".join(geom_lines) + "\n")
```

### 2. Articulated optical bench — knobs, clamps, rails

```
Task Progress:
- [ ] Step 1: Split by articulation: rail/base, carrier, clamp body, knob, screw, lever
- [ ] Step 2: Normalize units; small parts (< 5 cm) are often exported in mm
- [ ] Step 3: Simplify dense GS surfaces via Open3D quadric decimation
- [ ] Step 4: For each link: repair (trimesh → manifold3d if needed) then CoACD
- [ ] Step 5: Knobs/screws → primitive cylinders/capsules (skip knurling in collision)
- [ ] Step 6: For SAPIEN: use add_multiple_collisions_from_file per link
- [ ] Step 7: For Genesis: disable built-in convexify if pre-computed hulls provided
- [ ] Step 8: Emit URDF <collision> per link or MJCF body tree
```

Decompose *per link*, not on the whole assembled bench. Knurling and fine threads are visual-only; collision for knobs is always a cylinder or capsule approximation.

```python
import open3d as o3d, trimesh, coacd, numpy as np
from pathlib import Path

def simplify_open3d(path: Path, target_tri: int = 3000) -> trimesh.Trimesh:
    o3m = o3d.io.read_triangle_mesh(str(path))
    o3m = o3m.simplify_quadric_decimation(target_number_of_triangles=target_tri)
    verts = np.asarray(o3m.vertices); faces = np.asarray(o3m.triangles)
    return trimesh.Trimesh(vertices=verts, faces=faces, process=True)

def knob_to_capsule_mjcf(path: Path, name: str, density_kg_m3: float = 1180.0) -> str:
    m = trimesh.load(str(path), force="mesh")
    m.apply_scale(0.001)  # mm → m if needed
    r = float(np.max(m.extents[:2])) / 2.0
    h = float(m.extents[2])
    return (f'<geom name="{name}_col" type="capsule" '
            f'size="{r:.5g} {h/2:.5g}" contype="1" conaffinity="1" margin="5e-4"/>')

clamp_mesh = simplify_open3d(Path("clamp_body.stl"), target_tri=2500)
V = np.asarray(clamp_mesh.vertices, dtype=np.float64)
F = np.asarray(clamp_mesh.faces,    dtype=np.int64)
parts = coacd.run_coacd(coacd.Mesh(V, F), threshold=0.05, max_convex_hull=32)
for i, (v, f) in enumerate(parts):
    trimesh.Trimesh(v, f, process=True).export(f"clamp_col_{i:03d}.stl")

print(knob_to_capsule_mjcf(Path("adjustment_knob.stl"), "adj_knob"))
```

### 3. SEM sample stage — isolated PyMeshLab repair

```
Task Progress:
- [ ] Step 1: Load stage plate, tilt cradle, screw drive, shutter, sample holder
- [ ] Step 2: Simplify each part (Open3D or trimesh quadric decimation)
- [ ] Step 3: Subprocess-call PyMeshLab GPL venv for hole closing when trimesh fails
- [ ] Step 4: Reload and validate watertightness
- [ ] Step 5: Compute mass properties at part-appropriate density
- [ ] Step 6: Run CoACD; emit <inertial> with full inertia tensor + collision mesh set
```

```python
# pymeshlab_worker.py — run ONLY inside .venv-pymeshlab-gpl
import argparse, sys, pymeshlab as ml

def safe_filter(ms, name, **kw):
    try:
        defaults = ms.filter_parameter_values(name)
        kw = {k: v for k, v in kw.items() if k in defaults}
    except Exception:
        kw = {}
    try:
        ms.apply_filter(name, **kw)
    except Exception as exc:
        print(f"PyMeshLab skipped {name}: {exc}", file=sys.stderr)

ap = argparse.ArgumentParser()
ap.add_argument("--input", required=True); ap.add_argument("--output", required=True)
args = ap.parse_args()
ms = ml.MeshSet(); ms.load_new_mesh(args.input)
# NOTE: meshing_decimation_quadric_edge_collapse attribute may not exist in 2025.7
# (PyMeshLab #450). Always gate with safe_filter / filter_parameter_values.
safe_filter(ms, "meshing_remove_duplicate_vertices")
safe_filter(ms, "meshing_repair_non_manifold_edges")
safe_filter(ms, "meshing_repair_non_manifold_vertices")
safe_filter(ms, "meshing_close_holes", maxholesize=100)
ms.save_current_mesh(args.output)
```

```python
import subprocess, numpy as np, trimesh, coacd
from pathlib import Path

mesh = trimesh.load("stage_plate.stl", force="mesh")
mesh.apply_scale(0.001)            # mm → m
mesh.process(validate=True)
if len(mesh.faces) > 3000:
    mesh = mesh.simplify_quadric_decimation(face_count=3000, aggression=3)
mesh.export("stage_tmp.stl")
subprocess.run([".venv-pymeshlab-gpl/bin/python", "pymeshlab_worker.py",
                "--input", "stage_tmp.stl", "--output", "stage_repaired.stl"],
               check=True, timeout=120)
mesh = trimesh.load("stage_repaired.stl", force="mesh")
assert mesh.is_watertight, "stage not watertight"
mesh.density = 2700.0              # aluminium stage
mp = mesh.mass_properties
print(f"mass={mp['mass']:.4f} kg  com={mp['center_mass']}")
V = np.asarray(mesh.vertices, dtype=np.float64)
F = np.asarray(mesh.faces,    dtype=np.int64)
parts = coacd.run_coacd(coacd.Mesh(V, F), threshold=0.04, max_convex_hull=48)
for i, (v, f) in enumerate(parts):
    trimesh.Trimesh(v, f, process=True).export(f"stage_col_{i:03d}.stl")
```

## When to use vs alternatives

Use this skill when segmented visual meshes must become stable rigid-body collision assets for MuJoCo/SAPIEN/Isaac/Genesis. Covers chambers, knobs, stages, brackets, tools, racks, bottles, rigid harnesses, and fixture hardware.

**CoACD** (MIT, active, 1.0.10): default convex decomposer. Use `-rm` flag (real-metric mode, added 1.0.10) for physically consistent thresholds. Prefer over V-HACD in all new work.

**V-HACD**: archived/EOL. Do not introduce in new pipelines. Keep only for legacy reproducibility.

**manifold3d** (Apache-2.0, 3.4.1): robust manifold repair and boolean ops. Replaces ManifoldPlus in this pipeline (ManifoldPlus is non-commercial only).

**PyMeshLab** (GPL-3.0, 2025.7.post1): subprocess-isolated repair pass for stubborn non-manifold topology when trimesh + manifold3d cannot close the mesh. Never import directly into an MIT/Apache pipeline.

**pytetwild / fTetWild** (MPL-2.0, 0.2.3): tetrahedral meshing for FEM analysis or volumetric repair inspection. Not a convex-collider exporter; use only when you need tet meshes.

**Open3D** (MIT, 0.19.0): simplification (`simplify_quadric_decimation`) and point-cloud cleanup upstream of this skill. Use when source is a dense 3DGS point cloud or high-poly surface mesh.

**ManifoldPlus**: non-commercial license — do **not** use in this pipeline.

**Blender bpy**: GPL — isolate in a subprocess if used for manual artist cleanup.

Do NOT use convex decomposition on long cables/rods/hoses — use primitive capsule chains. Do NOT compute inertia from non-watertight meshes. For 3D reconstruction defer to cat 23, segmentation to cat 24, affordance to cat 25.

## Common issues

- **PyMeshLab #450 (Dec 2025): `meshing_decimation_quadric_edge_collapse` attribute missing in 2025.7.** `AttributeError: 'pymeshlab.pmeshlab.MeshSet' object has no attribute 'meshing_decimation_quadric_edge_collapse'`. Always gate filter calls with `safe_filter()` pattern that uses `filter_parameter_values()` introspection; pin `pymeshlab==2025.7.post1`.

- **trimesh #2264 (Aug 2024): wheel build failures for `manifold3d`/`vhacdx` in Docker.** Occurs when installing `trimesh[easy]` in a container without build tools. Solution: install `trimesh` core only; add `manifold3d` and other extras explicitly; ensure cmake/gcc are present in the Docker image base.

- **CoACD #71 (Jun 2025): hull-merge crash with aggressive `max_convex_hull` constraints.** Do not force `max_convex_hull=1` on complex meshes. Keep hull counts reasonable; fall back to primitive approximations for cables and rods. CoACD 1.0.10 introduced a minimal build mode; update if on older versions.

- **libigl `__version__` AttributeError.** Python docs state `igl.__version__` was removed in recent releases. Use `importlib.metadata.version("libigl")` instead.

- **Inertia from thin shells.** Thin visual shells have near-zero volume and unreliable mass properties. Use a solid convexified proxy, manufacturer mass data, or a manifold-repaired watertight volume for `<inertial>` tags.

- **MuJoCo treats non-convex mesh geoms as their convex hull.** Any visual mesh used directly as a geom loses concavity silently. Always output per-decomposed named hull files, verify in simulation with `geom.contype`/`conaffinity` set, and inspect contact forces during first run.

- **SAPIEN non-convex shapes restricted to static/kinematic.** If `add_multiple_collisions_from_file` produces a non-convex component (e.g. open shell), it is downgraded to trigger-only. Run CoACD before SAPIEN import so all components are convex.

- **Genesis auto-convexify overrides pre-computed hulls.** Call `entity.load_mesh(..., convexify=False, decimate=False)` when your pipeline has already produced named hulls; otherwise Genesis silently re-runs its own decomposition and discards yours.

## Key CLI and API surface

```bash
# CoACD Python API (primary)
python -c "
import coacd, numpy as np, trimesh
m = trimesh.load('part.stl', force='mesh')
cm = coacd.Mesh(np.asarray(m.vertices, dtype=np.float64),
                np.asarray(m.faces,    dtype=np.int64))
parts = coacd.run_coacd(cm, threshold=0.03, mcts_iterations=200,
                         preprocess_mode='auto', max_convex_hull=64, seed=7)
print(len(parts), 'hulls')
"

# CoACD CLI with real-metric mode (1.0.10+)
python -m coacd -i input.obj -o output.obj -rm

# fTetWild / pytetwild (tet meshing, not collision output)
python -c "import pytetwild; pytetwild.tetrahedralize_file('part.obj', 'part.msh', l=0.03, e=1e-3)"

# Open3D quadric decimation
python -c "
import open3d as o3d
m = o3d.io.read_triangle_mesh('part.stl')
m = m.simplify_quadric_decimation(target_number_of_triangles=3000)
o3d.io.write_triangle_mesh('part_decimated.stl', m)
"

# manifold3d watertight repair
python -c "
import manifold3d as mf, numpy as np, trimesh
mesh = trimesh.load('part.stl', force='mesh')
man = mf.Manifold(mf.Mesh(
    vert_properties=np.asarray(mesh.vertices, dtype=np.float32),
    tri_verts=np.asarray(mesh.faces, dtype=np.uint32)))
out = man.to_mesh()
trimesh.Trimesh(out.vert_properties, out.tri_verts).export('part_manifold.stl')
"

# libigl manifold check (version via importlib, not igl.__version__)
python -c "
import igl, importlib.metadata, numpy as np
print('libigl', importlib.metadata.version('libigl'))
F = np.load('faces.npy')
print('edge manifold:', igl.is_edge_manifold(F))
"

# USD mesh export (usd-core 26.5)
python -c "
from pxr import Usd, UsdGeom
stage = Usd.Stage.CreateNew('collision.usda')
mesh  = UsdGeom.Mesh.Define(stage, '/CollisionMesh')
# populate: mesh.GetPointsAttr(), GetFaceVertexCountsAttr(), GetFaceVertexIndicesAttr()
stage.Save()
"

# PyMeshLab repair (GPL — run in isolated venv only)
python -c "
import pymeshlab as ml
ms = ml.MeshSet()
ms.load_new_mesh('part.obj')
ms.apply_filter('meshing_close_holes', maxholesize=100)
ms.save_current_mesh('part_closed.obj')
"
```

## Advanced topics

- Full GitHub issue tracker with reproduction notes: `references/issues.md`
- Audit log schema and per-part volume-error thresholds: `references/issues.md`
- URDF/MJCF asset snippet templates for each engine: see `references/api.md` (if present)

## Resources

- CoACD: https://github.com/SarahWeiii/CoACD — MIT, active (1.0.10, Apr 2026)
- trimesh: https://github.com/mikedh/trimesh — MIT, 4.12.2 May 2026
- manifold3d: https://github.com/elalish/manifold — Apache-2.0, 3.4.1 Mar 2026
- libigl Python: https://github.com/libigl/libigl-python-bindings — MPL-2.0, 2.6.2 Mar 2026
- pytetwild: https://github.com/pyvista/pytetwild — MPL-2.0, 0.2.3 Feb 2026
- PyMeshLab: https://github.com/cnr-isti-vclab/PyMeshLab — GPL-3.0, 2025.7.post1 Jan 2026
- Open3D: https://github.com/isl-org/Open3D — MIT, 0.19.0 Jan 2025
- OpenUSD / usd-core: https://github.com/PixarAnimationStudios/OpenUSD — TOST-1.0, 26.5 Apr 2026
- MuJoCo XML reference: https://mujoco.readthedocs.io/en/stable/XMLreference.html
- Isaac Sim collision docs: https://docs.isaacsim.omniverse.nvidia.com
- SAPIEN 3.x actor builder: https://sapien.ucsd.edu/docs/latest/
- Genesis mesh morph docs: https://genesis-world.readthedocs.io/en/latest/
- CoACD paper: https://arxiv.org/abs/2205.02961
