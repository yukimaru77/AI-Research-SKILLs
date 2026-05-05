---
name: versioning-twins-with-ara
description: Packages a digital twin as a reproducible, versioned, citeable research artifact using OpenUSD 26.x as canonical scene format and ARA (Agent-Native Research Artifact) as the provenance and cognitive layer. Produces twin_manifest.yaml with SPDX/CycloneDX BOMs, OpenUSD layers with payload/variant composition, PROV-O + SLSA/in-toto attestations, OCI artifact bundles with cosign signatures, and a resurrection bundle for external auditors. Use after validating-digital-twins marks a build green and before deployment to NVIDIA Omniverse Kit 110, visionOS, MuJoCo, Isaac Lab, Genesis, or SAPIEN runtimes. Treats the twin as a versioned research artifact, not a pile of OBJ/PLY files.
version: 2.0.0
author: Orchestra Research
license: MIT
tags: [Digital Twin, OpenUSD, USDZ, ARA, Provenance, Versioning, Reproducibility, SemVer, NVIDIA Omniverse, OCI Artifacts, PROV-O, SLSA, SPDX]
dependencies: [openusd>=26.03, oras>=1.3, cosign>=2.0, uv>=0.5]
---

# Versioning Twins with ARA

Packages a digital twin as a reproducible, auditable, citeable Agent-Native Research Artifact. The twin is treated as a versioned research package — not a directory of meshes — with a declared public API, OCI-native distribution, PROV-O semantic provenance, SLSA/in-toto build attestation, and ARA Seal Level 2 evidence.

You PACKAGE. Sub-skills produced the assets; this skill stamps lineage, composition, and provenance.

**2026 baseline**: OpenUSD 26.05 preferred (26.03 minimum for first-class 3DGS). AOUSD Core Spec 1.0 as stable interchange target. Omniverse Kit 110 as preferred Omniverse runtime.

## Quick start

After [validating-digital-twins](../validating-digital-twins/SKILL.md) reports `status: validated`, this skill produces:

```
twin_package/
  ara/
    twin_manifest.yaml            # identity, USD profile, physical contract, provenance, BOM
    provenance.prov.jsonld        # PROV-O semantic lineage graph
    slsa.intoto.jsonl             # SLSA/in-toto build attestation
    evidence_bundle.json          # ARA evidence ledger (from compiler)
    claims.yaml                   # claims tied to evidence + uncertainty
    reviewers/
      rigor_review.md             # Seal Level 2 (from rigor-reviewer)
      safety_review.md            # manual review for SEM/laser/HV/biohazard
    reproducibility/
      environment.yml             # conda/pip export
      uv.lock                     # exact Python dependency lock
      pixi.lock                   # optional conda-lock
      containers.lock             # digest-pinned images
      command_log.sh              # replay script
      data_hashes.json            # sha256 for every input artifact
  usd/
    root.usda                     # thin interface layer
    layers/
      00_identity.usda
      20_semantics.usda
      30_articulation.usda
      40_collision.usdc
      50_visual_proxy.usdc
    payloads/
      visual_high.usdc
      collision_high.usdc
    captures/
      3dgs/2026-05-05_captureA/
        splat.usdc                # UsdVolParticleField3DGaussianSplat payload
        proxy_mesh.usdc
  sbom/
    spdx-3.0.1.json
    cyclonedx-hbom.json
  signatures/
    cosign.bundle
  release/
    twin_package_v{X.Y.Z}.tar.zst
    visionos_quicklook.usdz       # sealed delivery — NOT canonical source
    changelog.md
    known_limitations.md
```

Canonical format is OpenUSD (layered, payloaded, variant-rich). USDZ is a conservative Quick Look snapshot only.

## Architecture (cross-skill pipeline)

```
[ validating-digital-twins -> qa_report.json status=validated ]
        |
        v
versioning-twins-with-ara  (THIS SKILL)
   |  collect + sha256-hash every artifact  -> ara/reproducibility/data_hashes.json
   |  compose usd/root.usda
   |    thin usda interface + payload arcs
   |    variantSet "representation": proxy | render | splat
   |    variantSet "hardwareRev":    revA | revB | ...
   |    variantSet "sim_backend":    mujoco | isaac | genesis | sapien
   |  call 22/compiler         -> ara/evidence_bundle.json, claims.yaml
   |  call 22/research-manager -> ara/exploration_graph/
   |  call 22/rigor-reviewer   -> ara/reviewers/rigor_review.md  [Seal Level 2]
   |  freeze containers.lock + lockfiles
   |  emit PROV-O graph + SLSA attestation
   |  generate SPDX 3.0.1 + CycloneDX HBOM
   |  bump SemVer; sign OCI artifact with cosign (keyless)
   |  push OCI artifact to registry; cold-storage tar.zst + minisign
   v
[ deployment -> simulating-experiment-runs-in-twins ]
```

This skill calls the cat-22 ARA skills directly:

- [compiler](../../22-agent-native-research-artifact/compiler/SKILL.md) — assembles ARA evidence bundle + claims
- [research-manager](../../22-agent-native-research-artifact/research-manager/SKILL.md) — records exploration graph, attempts, decisions
- [rigor-reviewer](../../22-agent-native-research-artifact/rigor-reviewer/SKILL.md) — Seal Level 2 epistemic review of claims, limitations, hazards

## Common workflows

### Workflow 1 — Cut a release after a validated build

Goal: turn a green `qa_report.json` into a signed, hashed, OpenUSD-anchored OCI release.

Task Progress:
- [ ] R1. Verify `validation/qa_report.json` has `status: validated`
- [ ] R2. SHA-256 every artifact in `twin_package/` recursively → `ara/reproducibility/data_hashes.json`
- [ ] R3. Freeze environment: `uv pip freeze` → `uv.lock`; `conda env export` → `environment.yml`; record container digests → `containers.lock` (pin by digest, not tag)
- [ ] R4. Capture command log from dispatch trace → `ara/reproducibility/command_log.sh`
- [ ] R5. Author `usd/root.usda` — thin usda interface with sublayer references to role layers, payload arcs for heavy assets, and variantSets per policy below
- [ ] R6. Add 3DGS captures as `UsdVolParticleField3DGaussianSplat` payloads under `representation = "splat"` variant; never inline large splat arrays
- [ ] R7. Run `usdchecker usd/root.usda --variantSets representation,hardwareRev` — 0 errors required; fix with `usdfixbrokenpixarschemas` if needed
- [ ] R8. Call [compiler](../../22-agent-native-research-artifact/compiler/SKILL.md) → `ara/evidence_bundle.json`, `ara/claims.yaml`
- [ ] R9. Call [research-manager](../../22-agent-native-research-artifact/research-manager/SKILL.md) → `ara/exploration_graph/`
- [ ] R10. Call [rigor-reviewer](../../22-agent-native-research-artifact/rigor-reviewer/SKILL.md) → `ara/reviewers/rigor_review.md` (Seal Level 2 stamp required)
- [ ] R11. Manual safety review if SEM/laser/HV/biohazard equipment → `ara/reviewers/safety_review.md`
- [ ] R12. Emit `ara/provenance.prov.jsonld` (PROV-O semantic lineage) and `ara/slsa.intoto.jsonl` (build attestation)
- [ ] R13. Generate `sbom/spdx-3.0.1.json` (SPDX 3.0.1 Build+Software+Dataset profiles) and `sbom/cyclonedx-hbom.json`
- [ ] R14. Bump SemVer per policy; write `release/changelog.md` entry
- [ ] R15. Generate `ara/twin_manifest.yaml` — see [references/manifest-schema.md](references/manifest-schema.md) for full schema
- [ ] R16. Pack `release/twin_package_v{X.Y.Z}.tar.zst`; generate `release/visionos_quicklook.usdz` (flattened, self-contained, no custom schemas)
- [ ] R17. Sign OCI artifact with cosign keyless OIDC; sign cold-storage tar with minisign → `signatures/`
- [ ] R18. Push OCI artifact: `oras push ghcr.io/org/twins/{id}:{version} --artifact-type application/vnd.ara.twin.v1+tar`; attach referrers: SBOM, provenance, signatures, validator reports
- [ ] R19. Tag git `twin/<equipment_id>/v{X.Y.Z}`; hand off to [simulating-experiment-runs-in-twins](../simulating-experiment-runs-in-twins/SKILL.md)

### Workflow 2 — Patch release (capture unchanged, physics refit only)

Goal: bump PATCH after a joint refit without recapturing or retraining 3DGS.

Task Progress:
- [ ] 1. Verify `qa_report.json` status `validated` for new build
- [ ] 2. Diff `data_hashes.json` vs prior release — confirm only articulation layer and downstream URDF/USD changed
- [ ] 3. Re-hash only changed files; preserve all other digests
- [ ] 4. Update `changelog.md` PATCH entry documenting the specific joint/parameter change and improvement delta
- [ ] 5. Swap articulation payload in `usd/root.usda`; verify composition resolves cleanly
- [ ] 6. Run [rigor-reviewer](../../22-agent-native-research-artifact/rigor-reviewer/SKILL.md) on the diff only
- [ ] 7. Bump PATCH; repack; re-sign; push new OCI artifact tag

### Workflow 3 — Resurrection bundle for external auditor

Goal: give an external reviewer everything to deterministically reproduce the release from cold storage.

Task Progress:
- [ ] 1. Verify `ara/reproducibility/` is complete: `environment.yml`, `uv.lock`, `containers.lock`, `command_log.sh`, `data_hashes.json`
- [ ] 2. Confirm all raw captures, calibration files, and fiducial maps referenced in `data_hashes.json` are recoverable from cold storage (OCI or archive)
- [ ] 3. Provide `rebuild/rebuild.sh` — pulls digest-pinned container, mounts dataset, replays `command_log.sh`
- [ ] 4. Provide `rebuild/verify.sh` — re-hashes output and diffs vs `data_hashes.json`; report deviations
- [ ] 5. Include `rebuild/expected_hashes.json` and `rebuild/expected_outputs.json` with declared numeric tolerances
- [ ] 6. Provide `audit/flattened_layerstack.usda` and `audit/layer_inventory.csv` for USD review without large payload loads
- [ ] 7. Reviewer signs `ara/reviewers/external_audit.md` to complete ARA Seal Level 2 availability+functionality check

## Validation & quality gates

Run all gates before tagging the release. Block on any failure.

| Gate | Pass condition | Fail action |
|---|---|---|
| `qa_report.json` status | `validated` | block release |
| All artifacts in `data_hashes.json` | 100% coverage | recompute |
| `usd/root.usda` composition resolves | all references + payloads resolve | fix paths |
| USD variantSets present | `representation`, `hardwareRev`, `sim_backend` | author missing |
| `usdchecker usd/root.usda` | 0 errors | fix; run `usdfixbrokenpixarschemas` |
| Variant matrix smoke test | all declared variants load without errors | fix per variant |
| `ara/evidence_bundle.json` | produced by [compiler](../../22-agent-native-research-artifact/compiler/SKILL.md) | rerun ARA compile |
| `ara/reviewers/rigor_review.md` | Seal Level 2 stamp | rerun [rigor-reviewer](../../22-agent-native-research-artifact/rigor-reviewer/SKILL.md) |
| `safety_review.md` | present if SEM/laser/HV/biohazard | run manual review |
| SPDX + HBOM present | both files in `sbom/` | generate |
| cosign bundle valid | verifies against OCI digest | re-sign |
| Cold-storage paths resolvable | all raw capture digests resolvable | move to durable storage |
| `known_limitations.md` present | required for any release | author |
| `changelog.md` updated | required for any release | update |

### SemVer policy — twin public API

The twin's public API is: prim paths, semantic IDs, coordinate frames, units, joint names/axes/limits, sensor names/frames/intrinsics, collision contract, required USD schema plugins, and manifest schema version.

| Change | Bump | Examples |
|---|---|---|
| MAJOR | breaks public API | rename joint/frame, change units/up-axis, change defaultPrim, remove required variant, raise OpenUSD min in breaking way, change custom schema data model |
| MINOR | backward-compatible addition | add new representation variant, new sensor, new semantic labels (no existing meaning changed), new non-default delivery profile |
| PATCH | backward-compatible fix | fix texture paths, correct metadata typos, recalibrate within declared uncertainty, update checksums for same content |

Tag format: `twin/<equipment_id>/v{MAJOR}.{MINOR}.{PATCH}` (e.g. `twin/centrifuge_x200/v2.1.0`).

Use CalVer for capture session IDs (e.g. `2026-05-05_captureA`) and OCI digests as the immutable identity anchor.

### ARA Seal Level 2 checklist

| Category | Required |
|---|---|
| Availability | archived bundle with DOI or immutable OCI digest; license files; citation metadata (CITATION.cff) |
| Functionality | bundle unpacks cleanly; `verify.sh` runs; validator reports included; hardware/runtime requirements documented |
| Reusability | manifest schema documented; USD layers modular; variant policy documented; proxy load path usable without large payloads |
| Result validation | key claims mapped to artifacts; representative reproduction workflow; expected outputs + tolerances declared |
| Epistemic review | measured vs inferred vs simulated claims separated; calibration sources documented; uncertainty/tolerances declared; known failure modes listed; physical assumptions stated |
| Integrity | SPDX + HBOM present; PROV-O + SLSA attestation; cosign bundle; digest manifest |

## Common issues

| Symptom | Cause | Fix |
|---|---|---|
| `usdchecker` fails | broken payload/reference path | resolve paths; rebuild composition |
| OpenUSD 26.x rejects payload edit code | `Sdf.Payload` direct edits removed in 26.03 | update to supported payload-list APIs |
| Release tarball unexpectedly large | 3DGS splats inlined or baked into USDZ | move splats to `UsdVolParticleField3DGaussianSplat` payloads; ship USDZ light |
| visionOS Quick Look fails | composition features (payloads, custom schemas, PointInstancer) in USDZ | USDZ must be flattened, self-contained, no custom schemas; treat as separate delivery build |
| ARA bundle missing command for joint refit | dispatch trace not flushed before packaging | rebuild from `dispatch_trace.jsonl`; rerun [compiler](../../22-agent-native-research-artifact/compiler/SKILL.md) |
| Auditor cannot reproduce build | container tag drifted; missing digest pin | pin all images by digest in `containers.lock`; never rely on tags for reproducibility |
| `data_hashes.json` mismatch | raw captures moved between sessions | restore from cold storage; never edit raw files |
| Two builds claim same SemVer | tag collision | bump PATCH; never reuse version tags |
| PLY-format 3DGS scale wrong after conversion | PLY uses log-scale; USD particle field uses linear | run SPZ-to-USD converter (OpenUSD 26.05+); normalize scale attributes explicitly |
| Older USD assets fail in 26.x | Ndr removed (use Sdr); `.sdf` deprecated; crate write version 0.13.0 | run `usdfixbrokenpixarschemas`; re-validate after OpenUSD upgrade |
| Kit 107 runtime rejects 26.x-only schemas | Kit 107 ships USD 24.05 | use conservative interchange profile (25.11); do not require 26.x-only schemas for Kit 107 targets |

## Advanced topics

- **Full manifest schema with all required/optional fields**: [references/manifest-schema.md](references/manifest-schema.md)
- **OpenUSD 26.x layer composition recipes for lab equipment**: [references/openusd-composition.md](references/openusd-composition.md)
- **PROV-O graph patterns + SLSA attestation templates**: [references/provenance-patterns.md](references/provenance-patterns.md)
- **OCI artifact layout + ORAS push/pull workflow**: [references/oci-artifact-workflow.md](references/oci-artifact-workflow.md)

## Resources

### Cross-references

- [lab-equipment-twinning](../lab-equipment-twinning/SKILL.md) — orchestrator upstream
- [validating-digital-twins](../validating-digital-twins/SKILL.md) — must report green before this skill runs
- [simulating-experiment-runs-in-twins](../simulating-experiment-runs-in-twins/SKILL.md) — consumes signed release
- [compiler](../../22-agent-native-research-artifact/compiler/SKILL.md) — ARA evidence bundle assembly
- [research-manager](../../22-agent-native-research-artifact/research-manager/SKILL.md) — exploration graph recording
- [rigor-reviewer](../../22-agent-native-research-artifact/rigor-reviewer/SKILL.md) — Seal Level 2 epistemic review

### External anchors

- OpenUSD 26.x changelog — composition, payload, validation changes (26.03, 26.05)
- AOUSD Core Spec 1.0 — stable interchange conformance target (1.1 fast-follow: optional until ratified)
- NVIDIA Omniverse Kit 110 (2026-02) — GSplat integration, Vision Pro XR, nested rigid-body physics
- SPDX 3.0.1 — Build + Software + Dataset + AI profiles for BOMs and attestations
- CycloneDX HBOM / MBOM — hardware and manufacturing BOMs for lab equipment
- OCI Image Spec 1.1 — artifactType, subject, referrers API for SBOMs, signatures, attestations
- ORAS 1.3+ — OCI Layout cold-storage backup/restore with referrers
- W3C PROV-O — provenance ontology for `provenance.prov.jsonld`
- SLSA / in-toto — machine-verifiable build provenance and attestation
- Sigstore / cosign — keyless OCI artifact signing via OIDC + Rekor
- minisign — offline cold-storage tarball signing
