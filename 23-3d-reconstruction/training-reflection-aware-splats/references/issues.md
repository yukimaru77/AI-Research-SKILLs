# Known GitHub Issues — Reflection-Aware 3DGS Tools

Verified May 4, 2026. Issue status reflects that date. All issue numbers reference public GitHub trackers.

---

## Spec-Gaussian / Specular-Gaussians (ingra14m/Specular-Gaussians)

| Issue | Topic | Status | Fix |
|---|---|---|---|
| #2 | CUDA OOM on RTX 4090 | Open | Maintainer: synthetic data should not OOM; for real-world scenes use anchor Gaussian or `use_filter=True` |
| #9 | OOM in render.py (49.97 GiB attempted) | Open | Use `--use_filter` (older code) or set `use_filter=True`; current render path uses filtering for `is_real` |
| #13 | Anchor training `ASGRender(num_theta=2, num_phi=4)` TypeError | Open | Maintainer committed new code but recommends non-anchor training for quality |
| #15 | `forward() got unexpected keyword 'means2D_densify'` | Open | Rasterizer API mismatch; reinstall this repo's submodule in a clean env; no upstream patch visible |
| #21 | Normal interpretation / `center_normal` question on smooth surfaces | Open | No documented fix; treat smooth-surface normals as unreliable |

**Last code commit**: 2024-11-15 ("update training scripts for current version"). No GitHub releases. Code appears dormant after late 2024.

---

## Ref-Gaussian (fudan-zvg/ref-gaussian)

| Issue | Topic | Status | Fix |
|---|---|---|---|
| #2 | `submodules/raytracing` compile error: Eigen/CUDA half-operator ambiguity on Windows CUDA 11.7 | Open | Ubuntu Docker with CUDA 11.7/Torch 2.0 or CUDA 11.8/Torch 2.0 works; try `apt-get install libeigen3-dev`; alternate raytracing fork for higher CUDA |
| #5 | CUDA illegal memory access in `depth_to_normal` during training | Closed as completed | No fix comment visible |
| #8 | Relighting / new environment map loading not documented | Open | User workaround: place HDR as `output/<model>/point_cloud/iteration_50000/point_cloud.hdr`; run `python eval.py --white_background --save_images --model_path <path> --relight`; not confirmed official |
| #9 | Cannot reproduce paper metrics; weird normal map; floaters/distortions after ~20k iters | Open | No maintainer fix |

**License caveat**: root LICENSE is MIT (Fudan Zhang Vision Group 2025), but LICENSE.md contains Inria/MPII Gaussian-Splatting non-commercial terms. GitHub reports "MIT, Unknown licenses found." Treat as requiring legal audit for commercial use.

**scipy conflict**: requirements.txt pins `scipy==1.15.1` which requires Python >=3.10, conflicting with the README's Python 3.8 env. Workaround:
```bash
pip install "scipy==1.10.1"
```

**Last code commit**: 2025-03-18 ("Create LICENSE"). No GitHub releases. Open issues continue into 2026.

---

## GaussianShader (Asparagus15/GaussianShader)

| Issue/PR | Topic | Status | Fix |
|---|---|---|---|
| #8 | `delta_normal_loss` bug | Closed | Maintainer says fixed in latest update |
| #11 | `predicted_normal_loss` blurs results | Closed | No documented fix in comments |
| #19 | `get_minimum_axis` normal-axis selection is wrong/ambiguous | Open | PR #20 open and unmerged — fixes one file |
| PR #20 | Fix `get_minimum_axis` | Open (unmerged) | Apply patch manually from PR |
| #23 | Cutlass package not found | Open | GaussianShader may run without Cutlass |
| #24 | Saving/loading env map changes output quality | Open | User workaround: save/load `EnvironmentLight.state_dict()` instead of HDR file |
| #25 | Mip-NeRF360 performance drop vs vanilla 3DGS | Open | No comments |
| #33 | Normal delta parameters have `requires_grad=False` | Open | No comments |
| #34 | 2025 install failure with Python 3.7 env file | Open | No verified fix; packages aged out of channels |

**Flag discrepancy**: README documents `--brdf_env 512` but current `arguments/__init__.py` exposes `--brdf_envmap_res`. Use `--brdf_envmap_res 512` with current code.

**License**: LICENSE.md is non-commercial Inria Gaussian-Splatting research/evaluation license. Unsafe for commercial use.

**Last code commit**: 2024-01-25 ("Update README.md"). No GitHub releases. Stale.

---

## 3DGS-DR / Deferred Reflection (gapszju/3DGS-DR)

| Issue/PR | Topic | Status | Fix |
|---|---|---|---|
| PR #8 | Typo in Python train.py command in train.sh | Merged 2024-07-12 | Use current main |
| PR #9 | `tb_writer.add_image` AttributeError when TensorBoard is None | Merged 2024-07-12 | Use current main; or patch: `if tb_writer: tb_writer.add_image(...)` |
| #7 | OOM on real Ref-Real scenes (24 GB GPU) | Closed | Use 1/8 resolution for sedan; 1/4 for other Ref-Real scenes; rename `images_4` to `images` if needed |
| #12 | Reference environment map source | Open | Comments point to NMF repo backgrounds |
| #13 | Render reflection color map without background | Open | No comments |
| #16 | Why use `_c7` rasterizer? | Open | Maintainer: PyTorch SH color is slower; CUDA kernel restricts `means2D` gradient to base color; if feeding RGB/R/normal directly, reduce densification threshold |
| #18 | `diff-gaussian-rasterization_c7` backward gradient shape `[*,3]` vs `[*,7]` | Open | Namespace collision between c3 and c7; use fresh Docker; rename namespaces; or use only c7 |
| #20 | OOM on sedan with 24 GB 3090/4090; NaN after user-side FP16 hacks | Open | Maintainer confirms low-res data expected; FP16 not officially supported |

**License**: No top-level LICENSE or LICENSE.md found. Bundled `submodules/diff-gaussian-rasterization_c7/LICENSE.md` is Gaussian-Splatting non-commercial. Treat as non-commercial research unless authors clarify.

**Last code commit**: 2024-07-12 (merged PR #8/#9). No releases. Stale.

---

## Ref-GS (YoujiaZhang/Ref-GS)

| Issue | Topic | Status | Fix |
|---|---|---|---|
| #2 | Poor Ref-Real reconstruction / normal / mesh | Closed | Root cause: user had not switched to this repo's `gaussian_renderer`; use this repo's package |
| #4 | Hardcoded `CUDA_VISIBLE_DEVICES=2` in train.py | Closed | Maintainer agreed default should be GPU 0, but current train.py still hardcodes GPU 2; **patch manually** before training on single-GPU workstations |
| #7 | Ref-Real resolution protocol | Open | Maintainer says they followed 3DGS-DR; on-the-fly downsampling vs provided `images_4`/`images_8` affects metrics |
| #10 | Missing `nero2blender.py` | Open | Maintainer says script comes from GaussianShader |

**Hardcoded GPU patch** (required on single-GPU workstations):
```python
# In train.py and train-real.py, find and change:
os.environ["CUDA_VISIBLE_DEVICES"] = "2"
# to:
os.environ["CUDA_VISIBLE_DEVICES"] = "0"
# or remove the line entirely and let CUDA_VISIBLE_DEVICES from the shell take effect
```

**No root render.py**: testing is via `notebook/test.ipynb` or `train-real.py` eval path; there is no standard root `render.py` or `eval.py`.

**License**: root LICENSE is MIT (Youjia Zhang 2025). Verify third-party CUDA submodule licenses before redistribution.

**Last code commit**: 2025-05-15 ("Update README.md"). Most recently maintained of the five tools.

---

## Environment-map leakage — common mitigation

No public issues were found explicitly titled "environment-map energy leakage / ghost geometry baked into envmap." The practical mitigation is present in 3DGS-DR and Ref-GS via explicit flags:

```bash
# 3DGS-DR and Ref-GS / Ref-Gaussian:
--use_env_scope
--env_scope_center <cx> <cy> <cz>
--env_scope_radius <r>
```

Set the scope to the smallest sphere enclosing the target object in COLMAP coordinates. Verify by rendering env maps at early checkpoints (iteration 3000–5000).

Additional mitigation: mask background before training; provide clean alpha/mask directory or RGBA images where the repo supports it.

---

## NaN / training divergence

No public NaN-in-shading issues were found for Spec-Gaussian, Ref-Gaussian, GaussianShader, or Ref-GS. 3DGS-DR issue #20 contains a user-reported NaN after user-side FP16 modifications (not upstream code). FP16 training is not officially supported in any of these repos.
