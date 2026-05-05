---
name: authoring-urdf-mjcf-usd
description: 'Programmatically authors lab-equipment digital-twin descriptions in three synchronized formats — URDF for ROS-style interchange, MJCF for MuJoCo physics simulation, and USD for scene composition — from a single neutral component dictionary. Use when downstream pipelines must consume the same articulated asset (SEM stage, optical bench, vacuum chamber, microscope objective) in multiple simulator/renderer ecosystems and a single Python source of truth is required for joint kinematics, mesh references, units, and limits. NOTE — usd-core ships under LicenseRef-TOST-1.0 (Tomorrow Open Source Technology License v1.0), not Apache/MIT — flag for legal review before commercial redistribution.'
version: 2.0.0
author: Orchestra Research
license: MIT
tags: [Physics Simulation, Digital Twin, URDF, MJCF, USD, Authoring, Kinematics]
dependencies: [yourdfpy==0.0.60, mujoco==3.8.0, usd-core==26.5, urchin==0.0.30, numpy>=2.0, lxml>=4.9, trimesh>=4.0]
---

# authoring-urdf-mjcf-usd

## Quick start

Authors lab-equipment digital twins in URDF, MJCF, and USD from a single Python dictionary. Baseline (2026-05-05): yourdfpy 0.0.60 (2026-01-23, MIT), mujoco 3.8.0 (2026-04-24, Apache-2.0, **Python >=3.10**), usd-core 26.5 (2026-04-24, **LicenseRef-TOST-1.0** — not Apache/MIT, gate USD export behind a config switch in permissive-only environments; **Python >=3.9,<3.15**), urchin 0.0.30 (2025-10-21, MIT, maintained urdfpy fork, **Python >=3.9**). urdfpy 0.0.22 (2020-05-31, MIT) is legacy read-only fallback only.

OpenUSD versioning note: GitHub/docs tag is `26.05`; PyPI normalises to `26.5`. Always use `usd-core==26.5` in pip pins. OpenUSD 25.08 landed on GitHub July 31 2025 (announced Aug 11 2025) and introduced meaningful deprecations: Ndr deprecated in favour of Sdr, `.sdf` file format removed, Embree 3 support marked for future removal.

```bash
python3.11 -m venv .venv && . .venv/bin/activate
python -m pip install --upgrade pip setuptools wheel
python -m pip install \
  "yourdfpy==0.0.60" \
  "mujoco==3.8.0" \
  "usd-core==26.5" \
  "urchin==0.0.30" \
  "numpy>=2,<3" "lxml>=4.9,<6" "trimesh>=4,<5"
# For MuJoCo USD extras (optional): mujoco[usd]==3.8.0
python -c "import yourdfpy, mujoco; from pxr import Usd; print('ok')"
```

**API corrections vs older docs:**
- `write_xml()` returns an XML element tree — not a file writer.
- `write_xml_string(encoding="unicode")` returns a Python `str`; bare `write_xml_string()` returns `bytes`.
- `write_xml_file("robot.urdf")` writes to disk.
- `URDF.load_from_string` / `from_xml_string` do not exist in 0.0.60 (issue #54, open). Use `URDF.load(path)` or temp files.
- urchin: `URDF.load(path)` requires a `str`, not `pathlib.Path` (issue #35). Call `str(path)` first.

## Common workflows

### 1. SEM digital twin — 3-axis prismatic stage + revolute magnification knob

```
Task Progress:
- [ ] Step 1: Define canonical joint dictionary (parent, child, type, axis, limits)
- [ ] Step 2: Emit URDF with serial intermediate links for XYZ chain + continuous knob
- [ ] Step 3: Build MJCF via MjSpec: slide joints for XYZ, unlimited hinge for knob
- [ ] Step 4: Compile with spec.compile(), validate no mjMINVAL mass errors
- [ ] Step 5: Emit USD Xforms with joint metadata in sidecar /World/_joint_metadata Scope
- [ ] Step 6: Verify URDF axes match MJCF axes; run write_xml_string() sanity check
- [ ] Step 7: Save artifacts under out/sem/{sem.urdf, sem.xml, sem.usda}
```

URDF cannot attach one child link to three parents; each prismatic axis requires its own intermediate link (`stage_x_link`, `stage_y_link`, `stage_z_link`). The magnification knob is `continuous` in URDF and an unlimited `hinge` in MJCF.

```python
from yourdfpy.urdf import URDF, Robot, Link, Joint, Limit
import mujoco
from pxr import Usd, UsdGeom, Sdf, Gf

SEM_JOINTS = {
    "stage_x": {"type": "prismatic", "parent": "chamber",
                "child": "stage_x_link", "axis": [1, 0, 0], "limits": [-0.05, 0.05]},
    "stage_y": {"type": "prismatic", "parent": "stage_x_link",
                "child": "stage_y_link", "axis": [0, 1, 0], "limits": [-0.05, 0.05]},
    "stage_z": {"type": "prismatic", "parent": "stage_y_link",
                "child": "stage_z_link", "axis": [0, 0, 1], "limits": [0.0, 0.05]},
    "magnification_knob": {"type": "continuous", "parent": "chamber",
                           "child": "mag_knob", "axis": [0, 0, 1], "limits": None},
}

# --- URDF ---
def sem_urdf():
    links = [Link(n) for n in
             ["chamber", "stage_x_link", "stage_y_link", "stage_z_link", "mag_knob"]]
    joints = []
    for name, jd in SEM_JOINTS.items():
        lim = (Limit(lower=jd["limits"][0], upper=jd["limits"][1],
                     effort=200.0, velocity=0.02)
               if jd["type"] == "prismatic" else None)
        joints.append(Joint(name=name, type=jd["type"],
                            parent=jd["parent"], child=jd["child"],
                            axis=jd["axis"], limit=lim))
    robot = Robot(name="sem_digital_twin", links=links, joints=joints)
    urdf = URDF(robot=robot)
    urdf.write_xml_file("out/sem/sem.urdf")
    xml_str = urdf.write_xml_string(encoding="unicode")
    return xml_str

# --- MJCF ---
def sem_mjcf():
    spec = mujoco.MjSpec()
    spec.modelname = "sem_digital_twin"
    chamber = spec.worldbody.add_body(name="chamber")
    chamber.add_geom(name="chamber_box", type=mujoco.mjtGeom.mjGEOM_BOX,
                     size=[0.4, 0.4, 0.4], mass=10.0)
    prev = chamber
    for ax_name, axis, limits in [
        ("stage_x", [1, 0, 0], [-0.05, 0.05]),
        ("stage_y", [0, 1, 0], [-0.05, 0.05]),
        ("stage_z", [0, 0, 1], [0.0, 0.05]),
    ]:
        body = prev.add_body(name=f"{ax_name}_link")
        body.add_geom(name=f"{ax_name}_geom", type=mujoco.mjtGeom.mjGEOM_BOX,
                      size=[0.05, 0.05, 0.02], mass=0.5)
        j = body.add_joint()
        j.name = ax_name
        j.type = mujoco.mjtJoint.mjJNT_SLIDE
        j.axis = axis
        j.limited = True
        j.range = limits
        prev = body
    knob = chamber.add_body(name="mag_knob")
    knob.add_geom(name="knob_geom", type=mujoco.mjtGeom.mjGEOM_CYLINDER,
                  size=[0.015, 0.02], mass=0.05)
    jk = knob.add_joint()
    jk.name = "magnification_knob"
    jk.type = mujoco.mjtJoint.mjJNT_HINGE
    jk.axis = [0, 0, 1]
    jk.limited = False
    model = spec.compile()           # raises on mjMINVAL mass/inertia errors
    xml = spec.to_xml()
    with open("out/sem/sem.xml", "w") as f:
        f.write(xml)
    return model

# --- USD ---
def sem_usd():
    stage = Usd.Stage.CreateNew("out/sem/sem.usda")
    world = UsdGeom.Xform.Define(stage, "/World")
    stage.SetDefaultPrim(world.GetPrim())
    UsdGeom.SetStageMetersPerUnit(stage, 1.0)
    UsdGeom.SetStageUpAxis(stage, UsdGeom.Tokens.z)   # robotics convention: Z-up
    for name in ["chamber", "stage_x_link", "stage_y_link", "stage_z_link", "mag_knob"]:
        UsdGeom.Xform.Define(stage, f"/World/{name}")
    for jname, jd in SEM_JOINTS.items():
        p = stage.DefinePrim(f"/World/_joint_metadata/{jname}", "Scope")
        p.CreateAttribute("lab:jointType", Sdf.ValueTypeNames.String).Set(jd["type"])
        p.CreateAttribute("lab:axis", Sdf.ValueTypeNames.Float3).Set(
            Gf.Vec3f(*jd["axis"]))
    stage.GetRootLayer().Save()
```

### 2. Optical bench — fixed breadboard + parameterized post array with tip/tilt mounts

```
Task Progress:
- [ ] Step 1: Accept n_posts, pitch, board dims, post height, tip/tilt limit (degrees)
- [ ] Step 2: Build breadboard base as fixed world child (MJCF source of truth)
- [ ] Step 3: Iterate posts: add cylinder geom at pos=[i*pitch, 0, post_height/2]
- [ ] Step 4: Nest two revolute bodies per mount: mount_i_tilt (Y-axis) → mount_i_tip (X-axis)
- [ ] Step 5: Set hinge limits in radians: limited=True, range=[-deg*pi/180, +deg*pi/180]
- [ ] Step 6: spec.compile() to validate; export to MJCF XML
- [ ] Step 7: Emit URDF tree with equivalent revolute joints; note lossy omissions
```

MJCF is source of truth; URDF is emitted second for ROS interchange. Each mount nests `tilt_i` (hinge axis `[0,1,0]`) then `tip_i` (hinge axis `[1,0,0]`). URDF revolute joints use `Limit(lower=-lim_rad, upper=lim_rad, effort=2.0, velocity=0.5)`.

```python
import math, mujoco

def build_optical_bench_mjcf(n_posts: int = 4, pitch: float = 0.075,
                              tip_limit_deg: float = 5.0) -> mujoco.MjSpec:
    spec = mujoco.MjSpec()
    spec.modelname = "optical_bench"
    lim = math.radians(tip_limit_deg)

    base = spec.worldbody.add_body(name="breadboard")
    base.add_geom(name="breadboard_geom", type=mujoco.mjtGeom.mjGEOM_BOX,
                  size=[n_posts * pitch / 2, 0.15, 0.015],
                  pos=[(n_posts - 1) * pitch / 2, 0, 0], mass=2.0)

    for i in range(n_posts):
        x = i * pitch
        post = base.add_body(name=f"post_{i}", pos=[x, 0, 0.08])
        post.add_geom(name=f"post_{i}_geom", type=mujoco.mjtGeom.mjGEOM_CYLINDER,
                      size=[0.006, 0.04], mass=0.08)

        tilt = post.add_body(name=f"mount_{i}_tilt", pos=[0, 0, 0.04])
        tilt.add_geom(name=f"tilt_{i}_geom", type=mujoco.mjtGeom.mjGEOM_BOX,
                      size=[0.01, 0.01, 0.005], mass=0.02)
        jt = tilt.add_joint()
        jt.name = f"tilt_{i}"
        jt.type = mujoco.mjtJoint.mjJNT_HINGE
        jt.axis = [0, 1, 0]
        jt.limited = True
        jt.range = [-lim, lim]

        tip = tilt.add_body(name=f"mount_{i}_tip")
        tip.add_geom(name=f"tip_{i}_geom", type=mujoco.mjtGeom.mjGEOM_BOX,
                     size=[0.01, 0.01, 0.005], mass=0.02)
        jp = tip.add_joint()
        jp.name = f"tip_{i}"
        jp.type = mujoco.mjtJoint.mjJNT_HINGE
        jp.axis = [1, 0, 0]
        jp.limited = True
        jp.range = [-lim, lim]

    spec.compile()
    return spec
```

### 3. Microscope objective — fixed base + revolute turret + prismatic focus

```
Task Progress:
- [ ] Step 1: Author stand_base (fixed), turret as revolute child (Z-axis, full rotation)
- [ ] Step 2: Author focus_slide as prismatic child of turret (Z-axis, [−0.02, 0.0])
- [ ] Step 3: Add objective_lens geom on focus_slide with realistic mass/inertia
- [ ] Step 4: Compile MJCF, confirm spec.to_xml() round-trips cleanly (check issue #2370)
- [ ] Step 5: Emit URDF with revolute + prismatic joints; use write_xml_file()
- [ ] Step 6: Emit USD; set UsdGeom.Tokens.z up-axis + meters; add UsdPhysics joints
- [ ] Step 7: Write loss_report.json if any MJCF-only features were dropped
```

```python
from pxr import Usd, UsdGeom, UsdPhysics, Gf

def build_microscope_usd(out_path: str = "out/microscope/scope.usda"):
    stage = Usd.Stage.CreateNew(out_path)
    world = UsdGeom.Xform.Define(stage, "/World")
    stage.SetDefaultPrim(world.GetPrim())
    UsdGeom.SetStageMetersPerUnit(stage, 1.0)
    UsdGeom.SetStageUpAxis(stage, UsdGeom.Tokens.z)

    base_xf   = UsdGeom.Xform.Define(stage, "/World/stand_base")
    turret_xf = UsdGeom.Xform.Define(stage, "/World/turret")
    focus_xf  = UsdGeom.Xform.Define(stage, "/World/focus_slide")

    # Use XformCommonAPI for simple translation/rotation/scale authoring
    UsdGeom.XformCommonAPI(turret_xf).SetTranslate(Gf.Vec3d(0.0, 0.0, 0.15))

    # Revolute: turret rotates around Z on stand_base
    rev = UsdPhysics.RevoluteJoint.Define(stage, "/World/joints/turret_revolute")
    rev.CreateBody0Rel().SetTargets([base_xf.GetPath()])
    rev.CreateBody1Rel().SetTargets([turret_xf.GetPath()])
    rev.CreateAxisAttr("Z")
    rev.CreateLowerLimitAttr(-180.0)   # degrees in USD
    rev.CreateUpperLimitAttr(180.0)

    # Prismatic: focus slide translates along Z on turret
    pri = UsdPhysics.PrismaticJoint.Define(stage, "/World/joints/focus_prismatic")
    pri.CreateBody0Rel().SetTargets([turret_xf.GetPath()])
    pri.CreateBody1Rel().SetTargets([focus_xf.GetPath()])
    pri.CreateAxisAttr("Z")
    pri.CreateLowerLimitAttr(-0.02)    # metres
    pri.CreateUpperLimitAttr(0.0)

    stage.GetRootLayer().Save()
    return stage
```

## When to use vs alternatives

Use this skill when the deliverable must include URDF interchange, MJCF simulation, and/or USD scene composition from a single canonical Python dictionary; when joint kinematics from articulation extraction must hand off to multiple simulator ecosystems; or when a digital twin needs ROS-style transport, MuJoCo accuracy, and USD/Omniverse downstream visualization.

| Need | Recommended tool |
|------|-----------------|
| Modern URDF parse/write (Python) | yourdfpy 0.0.60 |
| Lazy-mesh / FK-only URDF parse | urchin 0.0.30 (`lazy_load_meshes=True`) |
| Legacy URDF read-only compat | urdfpy 0.0.22 (unmaintained since 2022) |
| Physics simulation | mujoco 3.8.0 + MjSpec |
| Scene composition / rendering | usd-core 26.5 (flag LicenseRef-TOST-1.0) |
| USD + MuJoCo in one install | `mujoco[usd]==3.8.0` (adds USD extras) |
| Symbolic ROS articulation reasoning | Kineverse (GPLv3 — license incompatibility risk) |
| Tiny one-off fixture | Direct XML templating (not for production families) |

For 3D reconstruction defer to cat 23; segmentation/articulation extraction to cat 24; affordance VLM to cat 25; VR/web rendering to cat 26; pipeline orchestration to cat 28.

## Common issues

**yourdfpy #66 (2026-04-26, open): empty `<texture/>` crashes `write_xml`** — `filename=None` causes `TypeError: Argument must be bytes or unicode, got 'NoneType'`. PR #67 open but not merged into 0.0.60. Workaround: strip materials with `None` texture filenames before calling `write_xml_file` or `write_xml_string`.

**yourdfpy #54 (2024-05-09, open): no public `URDF.load_from_string`** — Use `URDF.load(path)` with a temp file. The private `_parse_robot` workaround in the issue is not stable API.

**yourdfpy #57/#58 (2025-03-13, open): mimic tags and ros2_control tags missing after round-trip** — `write_xml_file` silently drops `<mimic>` and `<ros2_control>` extension tags. Do not rely on yourdfpy for ROS 2 control tag round-trips; add those sections in a post-processing pass.

**yourdfpy #52 (2024-01-03, open): lxml 5.0.0 / libxml 2.12 parser incompatibility** — Pin `lxml>=4.9,<5.4` if you hit XML parse errors with system lxml ≥ 5.

**urchin #35 (2025-08-29, open): `URDF.load` rejects `pathlib.Path` objects** — Always pass `str(path)` to `urchin.URDF.load`.

**urchin #27 (2024-12-16, open): `package://` mesh URI handling** — ROS package URIs are not auto-resolved. Pre-resolve all `package://pkg/mesh.stl` to absolute paths before passing to urchin.

**MuJoCo #1742 (2024-06-18): "mass and inertia of moving bodies must be larger than mjMINVAL"** — Every moving body needs `mass`/`density` or explicit `<inertial>`. `spec.compile()` raises on zero-mass moving links; catch this in CI before saving artifacts.

**MuJoCo #1577 (2024-04-08): URDF→MJCF collision changed in 2→3 migration** — Do not use direct URDF import for final simulation; emit MJCF explicitly and inspect `contype`/`conaffinity`. Use `mujoco.mj_saveLastXML(path, model)` to inspect the converted XML.

**MuJoCo 3.8.0: `strippath` default changed** — In 3.8.0, URDF `strippath` defaults to `False` (was `True`). If imported URDF assets relied on stripped mesh paths, set `spec.compiler.strippath = True`.

**MuJoCo #3152 (2026-03-04, open): segfault in MjSpec tendon-path/attach workflow** — Avoid complex tendon+attach combinations until fixed. Reproduce with a tendon spanning attached sub-specs; test thoroughly before deploying.

**MuJoCo #3139 (2026-03-02, open): `MjSpec.from_file` fails on non-ASCII/UTF-8 paths on Windows** — Keep all model file paths ASCII on cross-platform CI. On Linux this is usually safe, but guard for mixed teams.

**MuJoCo #2370 (2025-01-17, closed): `MjSpec.to_xml()` omits inertial properties** — Closed; verify round-trip by reloading saved XML with `mujoco.MjSpec.from_string(xml)` and comparing inertials if your workflow depends on exact inertial preservation.

**OpenUSD #3734 (2025-07-17, closed) + #3020 (2024-03-26, closed): Windows backslash / case-mismatched paths fail on Linux** — Always write forward-slash POSIX asset paths; apply a `posix_asset_path()` sanitizer at USD export time.

**OpenUSD #3983 (2026-02-11, closed): `usd-core` PyPI wheel missing `usdShaders` plugin resources** — Update to usd-core 26.5 if shader preview surfaces are missing.

**OpenUSD #3622 (2025-05-06, open): Python 3.13 not supported in usd-core** — Pin Python <=3.12 for usd-core; the constraint is `Python >=3.9,<3.15` in current wheels but 3.13 wheels may not be available for all platforms.

**OpenUSD 25.08 deprecations** — `Ndr` deprecated in favour of `Sdr`; `.sdf` file format removed; Embree 3 support marked for future removal. Do not use the old `Ndr` API in new code.

**USD Y-up vs Z-up** — USD default fallback is Y-up if `upAxis` is not authored. Always call `UsdGeom.SetStageUpAxis(stage, UsdGeom.Tokens.z)` for robotics scenes.

## Advanced topics

For MJCF-only features (contact pairs, equality constraints, tendons, solver tuning) that cannot be represented in URDF, always emit a `loss_report.json` alongside the URDF:

```python
import json
from pathlib import Path

loss_report = {
    "source": "out/vacuum/vacuum_chamber.xml",
    "target": "out/vacuum/vacuum_chamber.urdf",
    "dropped": [
        {"format": "MJCF", "element": "contact/pair", "name": "door_seal_to_seat"},
        {"format": "MJCF", "element": "equality/weld", "name": "door_latch_locked"},
    ],
    "kept": [{"joint": "door_hinge", "type": "revolute",
              "limits_rad": [0.0, 1.5707963267948966]}],
}
Path("out/vacuum/loss_report.json").write_text(json.dumps(loss_report, indent=2))
```

**UsdPhysics for portable joint semantics** — `UsdPhysics.FixedJoint`, `RevoluteJoint`, `PrismaticJoint`, `SphericalJoint`, `DistanceJoint` are the portable OpenUSD physics schemas. For Isaac Sim / PhysX / Newton-specific features, add simulator-specific schemas on top of core UsdPhysics.

**UsdGeom.XformCommonAPI** — Use `UsdGeom.XformCommonAPI(prim).SetTranslate/SetRotate/SetScale()` for simple transform authoring on any Xformable prim; avoid direct xformOp authoring unless non-standard op orders are needed.

**MjSpec attach workflow** — Use `spec.attach(sub_spec)` for compositional model building (e.g., attaching a gripper to an arm). Known issue #2101: attaching multiple bodies from the same sub-spec with keyframes caused name collisions in MuJoCo 3.2.3 (closed). Known open issue #3152: tendon paths crossing attach boundaries can segfault in 3.8.0.

**MJCF `multiccd` (3.8.0 default: enabled)** — MuJoCo 3.8.0 enables `multiccd` by default, which changes collision behavior vs 3.7.x. Re-run contact validation after upgrading.

**urchin FK workflow** — For pure FK without mesh loading, prefer urchin over yourdfpy for speed:
```python
from urchin import URDF
robot = URDF.load(str(urdf_path), lazy_load_meshes=True)
fk = robot.link_fk(cfg={"x_slide": 0.010, "y_slide": -0.003, "focus_z": 0.001})
```

See `references/issues.md` for the full watchlist (yourdfpy #52/#54/#57/#58/#66/#67, MuJoCo #1577/#1742/#2101/#2353/#2370/#2427/#2896/#3139/#3152, OpenUSD #3020/#3622/#3734/#3983/#4050) with reproductions and workarounds.

## Resources

- yourdfpy source: https://github.com/clemense/yourdfpy
- yourdfpy docs: https://yourdfpy.readthedocs.io
- urchin (maintained urdfpy fork): https://github.com/fishbotics/urchin
- MuJoCo Python API + MjSpec: https://mujoco.readthedocs.io/en/stable/python.html
- MuJoCo XML reference: https://mujoco.readthedocs.io/en/stable/XMLreference.html
- OpenUSD source: https://github.com/PixarAnimationStudios/OpenUSD
- UsdPhysics API: https://openusd.org/release/api/usd_physics_page_front.html
- USD references and stages: https://openusd.org/release/api/class_usd_references.html
- usd-core PyPI (license: LicenseRef-TOST-1.0): https://pypi.org/project/usd-core/
- OpenUSD 25.08 release notes: https://github.com/PixarAnimationStudios/OpenUSD/releases/tag/v25.08
