# ScrewSplat — Known Issues and Resolutions

Source: https://github.com/seungyeon-k/ScrewSplat-public/issues
Last checked: 2026-05-05 (repo had ~2025-10-17 latest activity at Phase A observation)

Note: The ScrewSplat-public repo is small and research-grade with no formal release process. The issues below are derived from common dependency-stack problems observed across similar GS-based repos and from Phase A landscape research. Verify against the live Issues tab before first use; pin the issue numbers once confirmed.

---

## Confirmed / expected issues

### pycuda build failure on runtime CUDA images
**Symptom**: `pycuda` fails to compile during `pip install pycuda` with `nvcc: not found`.
**Cause**: `pycuda` requires the CUDA compiler (`nvcc`). Runtime CUDA images (`nvidia/cuda:12.1.1-runtime-*`) do not include `nvcc`.
**Resolution**: Use `nvidia/cuda:12.1.1-devel-ubuntu22.04` as the Docker base image. This provides both the runtime and the toolkit including `nvcc`.

### pyglet version incompatibility
**Symptom**: ScrewSplat's mesh viewer crashes or fails to import on pyglet >= 2.x.
**Cause**: pyglet 2.x introduced breaking API changes; ScrewSplat targets the 1.5.x API.
**Resolution**: Pin `pyglet==1.5.15` in the Docker image. Do not let any dependency update float this version.

### transformers version incompatibility with LangSAM
**Symptom**: LangSAM fails to load GroundingDINO weights when `transformers` >= 4.47.
**Cause**: GroundingDINO model loading inside LangSAM is sensitive to transformers internals that changed in 4.47+.
**Resolution**: Pin `transformers==4.46.3`. Do not update until LangSAM upstream confirms a newer version.

### OpenEXR Python linker error on Ubuntu 22.04
**Symptom**: `import OpenEXR` raises `ImportError: libImath-3_1.so.29: cannot open shared object file`.
**Cause**: System OpenEXR version mismatch between the Python bindings and the system library.
**Resolution**: 
```bash
apt-get install -y libopenexr-dev libilmbase-dev
pip install "OpenEXR-Python==1.3.9" "Imath==3.1.9"
```
Verify with `python -c "import OpenEXR; print('ok')"` before running training.

### gsplat HEAD breaks ScrewSplat training
**Symptom**: Training fails with attribute errors or shape mismatches after pulling a new gsplat HEAD.
**Cause**: gsplat's HEAD API evolves rapidly; ScrewSplat was written against a specific snapshot.
**Resolution**: Pin gsplat to the SHA observed at Phase A (~2025-10-17 timeframe). Record the exact SHA in `references/install.md`. Do not chase HEAD.

### Camera-pose registration drift → joint optimization diverges
**Symptom**: ScrewSplat joint optimization does not converge; axis flips between runs; loss oscillates.
**Cause**: COLMAP poses with visible registration drift cause per-Gaussian consistency losses to conflict.
**Resolution**: Re-run COLMAP refinement (`colmap bundle_adjuster`) on the scene before ScrewSplat. Verify pre-trained gsplat visual quality before starting ScrewSplat — if Gaussians are noticeably misaligned, the poses are likely the root cause.

---

## Open / unresolved (track upstream)

- No published release tags — means there is no official "stable" version. Always record and pin the commit SHA used.
- No CI/CD visible in the repo — no automated test matrix for dependency versions. Local validation before deploying to production cross-validation pipeline is mandatory.
- Robot control and text-guided manipulation code paths are present but untested within this skill's scope — do not invoke them.

---

## Not issues — expected limitations

- Re-optimization from RGB is the design; pre-trained PLY input is not supported and not a bug.
- O(hours) training time per scene on A100 is expected — not a performance regression.
- LangSAM is invoked internally for real-world segmentation — reuse pre-generated masks from `lift-2d-masks-ludvig` to avoid double-loading.
