---
name: qwen3-vl-affordance-prompter
description: 'Prompts Qwen3.6-27B or Qwen3.6-35B-A3B (current canonical Qwen vision model as of May 2026, Apache-2.0, vision built-in, no -VL suffix) locally on a single A100 80GB to predict articulation and affordance hypotheses for segmented 3DGS parts of lab equipment. Use after multi-view joint cards are rendered from a 3D Gaussian Splatting pipeline to obtain conservative joint_type, axis, anchor, range, semantic_label, and interaction_verbs as structured kinematic JSON. VLM output is a hypothesis generator validated downstream by geometry and physics. Ensemble fallbacks — InternVL3.5-14B, SpatialRGPT (region-aware), SpatialBot (RGB-D), MolmoPoint-8B (anchor pointing only).'
version: 2.0.0
author: Orchestra Research
license: MIT
tags: [VLM, Qwen3.6, InternVL3, SpatialRGPT, SpatialBot, Molmo, A100, vLLM, Affordance, Lab Equipment, SEM, Zero-Shot Prompting, JSON, 3DGS, URDF]
dependencies: [transformers>=4.57.1, torch>=2.8.0, vllm>=0.19.0, accelerate>=1.10,<2, pillow>=10,<12]
---

# qwen3-vl-affordance-prompter

**Current model (DT-verified, May 2026)**: `Qwen/Qwen3.6-27B` (throughput) and `Qwen/Qwen3.6-35B-A3B` (adjudication). Both are unified multimodal models — vision is built in from the start; there is **no -VL suffix**. Released April 2026, Apache-2.0. The directory name `qwen3-vl-affordance-prompter` is stable for backward compatibility.

Note: `Qwen/Qwen3-VL-8B-Instruct` and `Qwen/Qwen3-VL-32B-Instruct` (Oct 2025) still exist on HF but are the previous generation. Qwen3.5 (Feb 2026) and Qwen3.6 (Apr 2026) supersede them with native multimodal unified architectures.

Pipeline role: video → camera poses → 3DGS → cluster moving parts → **this skill (VLM affordance)** → URDF/physics → VR rendering.

## Quick start

Install:

```bash
uv venv --python 3.12 --seed .venv-qwen36
source .venv-qwen36/bin/activate
UV_TORCH_BACKEND=cu128 uv pip install "vllm>=0.19.0"
uv pip install "transformers>=4.57.1" "openai>=1.60,<2" "pillow>=10,<12" accelerate
```

Download checkpoints:

```bash
huggingface-cli download Qwen/Qwen3.6-27B     --local-dir ./models/Qwen3.6-27B
huggingface-cli download Qwen/Qwen3.6-35B-A3B --local-dir ./models/Qwen3.6-35B-A3B
```

Serve (image-only; `--limit-mm-per-prompt video=0` disables video reservation):

```bash
vllm serve Qwen/Qwen3.6-27B \
  --port 8000 \
  --dtype bfloat16 \
  --max-model-len 65536 \
  --gpu-memory-utilization 0.90 \
  --reasoning-parser qwen3 \
  --limit-mm-per-prompt image=8,video=0
```

Minimal Transformers inference (no extra utils, simplest path):

```python
import torch
from transformers import AutoModelForImageTextToText, AutoProcessor

model_id = "Qwen/Qwen3.6-27B"
model = AutoModelForImageTextToText.from_pretrained(
    model_id, torch_dtype=torch.bfloat16, device_map="auto",
    attn_implementation="flash_attention_2",
)
processor = AutoProcessor.from_pretrained(model_id)

messages = [{"role": "user", "content": [
    {"type": "image", "image": "file:///data/sem_view.jpg"},
    {"type": "text",  "text": "Return JSON: joint_type, axis, range, confidence."},
]}]

inputs = processor.apply_chat_template(
    messages, tokenize=True, add_generation_prompt=True,
    return_dict=True, return_tensors="pt",
).to(model.device)
inputs.pop("token_type_ids", None)

with torch.inference_mode():
    generated = model.generate(**inputs, max_new_tokens=512)

trimmed = generated[:, inputs["input_ids"].shape[-1]:]
print(processor.batch_decode(trimmed, skip_special_tokens=True)[0])
```

OpenAI-compatible vLLM client (image URL or base64):

```python
import base64
from openai import OpenAI

client = OpenAI(api_key="EMPTY", base_url="http://127.0.0.1:8000/v1")

with open("sem_view.jpg", "rb") as f:
    b64 = base64.b64encode(f.read()).decode()

resp = client.chat.completions.create(
    model="Qwen/Qwen3.6-27B",
    temperature=1.0, top_p=0.95, max_tokens=512,
    extra_body={"top_k": 20},
    messages=[{"role": "user", "content": [
        {"type": "image_url",
         "image_url": {"url": f"data:image/jpeg;base64,{b64}"}},
        {"type": "text", "text": "Return kinematic JSON for this SEM part."},
    ]}],
)
print(resp.choices[0].message.content)
```

Structured JSON output (vLLM >= 0.12 pattern; `guided_json` removed in 0.12.0):

```python
resp = client.chat.completions.create(
    model="Qwen/Qwen3.6-27B",
    messages=[...],
    response_format={"type": "json_schema",
                     "json_schema": {"name": "affordance", "schema": schema, "strict": True}},
    extra_body={"top_k": 20},
)
```

Non-thinking mode (faster, deterministic affordance JSON):

```python
resp = client.chat.completions.create(
    model="Qwen/Qwen3.6-27B",
    temperature=0.7, top_p=0.8, max_tokens=512,
    extra_body={"top_k": 20, "chat_template_kwargs": {"enable_thinking": False}},
    messages=[{"role": "user", "content": [
        {"type": "image_url", "image_url": {"url": f"data:image/jpeg;base64,{b64}"}},
        {"type": "text", "text": "Return affordance JSON: joint_type, axis, range."},
    ]}],
)
```

Visual token budget (Qwen3.6 patch size 16, images rounded to 32 px):
`visual_tokens ≈ ceil(H/32) × ceil(W/32)`. 512 px ≈ 256 tokens, 768 px ≈ 576, 1024 px ≈ 1024.

## Common workflows

### Workflow 1: SEM rotary valve handle

```
- [ ] Render 8 azimuth views with mask overlay and view label (az000…az315)
- [ ] Include parent chamber panel in at least 2 views
- [ ] Include coordinate triad in prompt text
- [ ] Run Qwen3.6-27B first (non-thinking mode for speed)
- [ ] Escalate to Qwen3.6-35B-A3B with thinking mode if confidence < 0.65
- [ ] Validate VLM axis by fitting cylinder to knob hub/shaft centerline
- [ ] Store range as "unknown" unless stops, tick marks, or clearance are visible
```

Prompt template:

```
You are inspecting a segmented SEM rotary valve handle.
Images: 8 turntable views. Highlighted mask = moving child part.
Coordinate frame: +Z toward operator, +X right in az000, +Y up.

Rules:
1. Prefer revolute only with visible evidence: round knob, shaft, hub,
   bearing, detents, tick marks, or rotational clearance.
2. Do not invent angular range; use "unknown" unless limits are visible.
3. Axis direction may be sign-ambiguous; normalize to unit length.
4. Return ONLY JSON. No prose.
```

Acceptance gate:

```python
def accept_rotary(pred):
    if pred.get("joint_type") != "revolute": return False
    if pred.get("confidence", 0.0) < 0.55: return False
    evidence = " ".join(i.get("evidence","") for i in pred.get("evidence_by_view",[])).lower()
    return any(c in evidence for c in ["shaft","hub","round","cylind","tick","detent","valve"])
```

### Workflow 2: Hinged chamber door

```
- [ ] Provide parent mask (chamber body) and child mask (door/cover)
- [ ] Provide hinge barrel close-ups and at least one oblique showing knuckles
- [ ] Ask axis through hinge barrel centers, NOT door centroid
- [ ] Verify with 3D: fit line through hinge cylinders or pin centers
```

Geometry verification stub:

```python
import numpy as np

def fit_hinge_axis(points_xyz):
    if points_xyz.shape[0] < 20:
        raise ValueError("Need >= 20 hinge points")
    origin = points_xyz.mean(axis=0)
    _, _, vh = np.linalg.svd(points_xyz - origin, full_matrices=False)
    return {"origin_xyz": origin.tolist(),
            "direction_unit_xyz": (vh[0] / np.linalg.norm(vh[0])).tolist()}

def axis_agreement(a, b):
    a, b = np.array(a)/np.linalg.norm(a), np.array(b)/np.linalg.norm(b)
    return abs(float(np.dot(a, b)))   # sign-invariant
```

### Workflow 3: Prismatic specimen stage

```
- [ ] Provide whole-stage view with highlighted moving carriage
- [ ] Provide close-ups of rails, dovetails, slots, linear bearings
- [ ] Provide close-ups of lead screw / micrometer knob if present
- [ ] Provide scale, ruler, CAD dimension, or known screw pitch
- [ ] Distinguish actuator rotation (revolute) from carriage translation (prismatic)
- [ ] Verify range from mesh/CAD endpoints, rail length, or point-cloud limits
```

Range sanity (clamp hallucinations):

```python
def clamp_stage_range(pred, measured_travel_mm):
    rng = pred.setdefault("range", {})
    if measured_travel_mm is None:
        rng.update(type="unknown", lower=None, upper=None,
                   confidence=min(rng.get("confidence", 0.0), 0.3))
        return pred
    rng.update(type="linear_mm", lower=0.0, upper=round(float(measured_travel_mm), 3),
               estimated_from="3D geometry measurement",
               confidence=max(rng.get("confidence", 0.0), 0.75))
    return pred
```

## When to use vs alternatives

- **Qwen3.6-27B**: primary throughput model; handles 1–8 images per part for fast JSON affordance hypotheses.
- **Qwen3.6-35B-A3B**: MoE architecture, 35B total/3B active; use when 27B returns low confidence or ambiguous joint type. Weights ≈ lighter than 35B dense; fits A100 with `--max-model-len 8192 --max-num-seqs 1`.
- **Qwen3-VL-8B/32B-Instruct** (Oct 2025): previous generation, still real on HF. Use only for reproducibility of late-2025 results; prefer Qwen3.6 for new work.
- **InternVL3.5-14B**: ensemble vote when Qwen3.6 output is unstable. 14B fits single A100 BF16; 38B requires 2×A100.
- **SpatialRGPT**: high-quality masks/boxes already available; region-specific spatial questions. Keep in separate conda env (Detectron2 + pydantic conflict with vLLM stack). Real issue: SpatialRGPT #21.
- **SpatialBot-3B**: RGB-D depth-aware sanity check (near/far, above/below, approach direction).
- **MolmoPoint-8B** (released 2026-03-18, Apache-2.0): point anchor helper only ("point to hinge pin center"). NOT a primary affordance classifier.
- **Qwen2.5-VL-72B-AWQ**: legacy fallback only; older Transformers throws `KeyError: 'qwen2_5_vl'`.

## Common issues

### OOM on A100 (Qwen3.6-35B-A3B)

MoE architecture means active params ≈ 3B, but full weights load. Use constrained settings:

```bash
vllm serve Qwen/Qwen3.6-35B-A3B \
  --dtype bfloat16 --max-model-len 8192 \
  --gpu-memory-utilization 0.85 \
  --max-num-seqs 1 \
  --reasoning-parser qwen3 \
  --limit-mm-per-prompt image=4,video=0
```

Real issue: QwenLM/Qwen3.6 #148 (image recognition HTTP 500 under load, Apr 2026).

### vLLM version mismatch

Qwen3.6 requires `vllm>=0.19.0`. Earlier releases lack the `--reasoning-parser qwen3` flag and Qwen3.6 model support. PyPI sequence: 0.11.2 (Nov 2025) → 0.12.0 (Dec 2025) → … → 0.19.0 (Apr 2026) → 0.20.1 (May 2026). Use current stable.

Real issue: QwenLM/Qwen3-VL #1477 (invalid vllm installation instruction at Qwen3-VL launch, Sep 2025).

### guided_json removed in vLLM 0.12.0

Use `response_format={"type":"json_schema", ...}` for vLLM >= 0.12. Do not use `extra_body={"guided_json": schema}` — removed in 0.12.0.

### vLLM chunked prefill + prefix caching error

Symptom: `Requested more deepstack tokens than available in buffer`. Workaround: disable chunked prefill or disable prefix caching. Real issue: vLLM #41485 (May 1, 2026).

### Multi-image OOM budget

27B safe budget: `max_pixels=768*768` (≈ 576 visual tokens); 35B-A3B: `max_pixels=512*512`. Limit to 8 images per prompt. Use `--limit-mm-per-prompt image=8,video=0` at serve time.

### SpatialRGPT pydantic / Detectron2

Use separate demo env with `gradio==4.27`, `deepspeed==0.13.0`, `gradio_box_promptable_image`, `detectron2 @ ff53992...`. Set `CUDA_HOME=/usr/local/cuda-12.1`. Real issue: SpatialRGPT #21.

### SpatialBot tensor device mismatch

Fix: `model.get_vision_tower().to("cuda")`. Real issues: SpatialBot #2, #4, #5, #6.

## Lab-equipment pitfalls

1. **Hallucinated revolute joints**: VLMs over-predict revolute for round caps. Mitigation: "Unknown is allowed. Do not classify as revolute unless shaft, hinge pin, hub, bearing, detent, tick mark, or rotational clearance is visible. List counterevidence before confidence."
2. **Axis sign**: `v` and `-v` are the same physical axis. Compare with `abs(np.dot(a, b))`.
3. **Range hallucination**: Models invent 90/180/360 deg. Policy: "If stops, limits, or clearance not visible, output `range.type='unknown'`."
4. **Hidden actuator**: SEM stages — rotary knob drives prismatic carriage. Prompt: "Classify the masked part, NOT the actuator. If knob rotates to move stage, output `actuator_joint='revolute'` and stage `joint_type='prismatic'`."
5. **Multi-image OOM**: keep visual-token budget tight (see above).
6. **Thinking mode latency**: Qwen3.6 defaults to thinking-enabled; for fast affordance JSON use `chat_template_kwargs: {enable_thinking: false}`.

## Advanced topics

### Geometry-first verification

```python
def final_joint_decision(vlm_pred, geom):
    jt = vlm_pred.get("joint_type")
    if geom.get("has_hinge_knuckles"): return "revolute"
    if geom.get("has_parallel_rails"): return "prismatic"
    if jt in {"revolute", "prismatic"} and vlm_pred.get("confidence", 0) >= 0.8:
        return jt
    return "unknown"
```

### Ensemble adjudication

```python
def needs_adjudication(pred):
    if pred.get("confidence", 0.0) < 0.65: return True
    if pred.get("joint_type") in {"compound", "unknown"}: return True
    if pred.get("range", {}).get("type") != "unknown" \
       and not pred.get("range", {}).get("evidence"): return True
    if pred.get("axis", {}).get("observability") in {"inferred", "unknown"}: return True
    return False
```

Adjudication order: Qwen3.6-27B → Qwen3.6-35B-A3B → InternVL3.5-14B → SpatialRGPT → geometry validator.

### MolmoPoint anchor extraction

```python
from transformers import AutoModelForImageTextToText, AutoProcessor
from PIL import Image
import torch

model = AutoModelForImageTextToText.from_pretrained(
    "allenai/MolmoPoint-8B", dtype=torch.float32, device_map="auto")
processor = AutoProcessor.from_pretrained("allenai/MolmoPoint-8B")
image = Image.open("hinge_view.jpg").convert("RGB")
messages = [{"role":"user","content":[
    {"type":"image","image":image},
    {"type":"text","text":"Point to the hinge pin center."},
]}]
inputs = processor.apply_chat_template(messages, add_generation_prompt=True,
    tokenize=True, return_dict=True, return_tensors="pt",
    return_pointing_metadata=True).to(model.device)
logits_processor = model.build_logit_processor_from_inputs(inputs)
outputs = model.generate(**inputs, max_new_tokens=128, logits_processor=logits_processor)
points = model.extract_image_points(outputs,
    token_pooling=inputs["token_pooling"],
    subpatch_mapping=inputs["subpatch_mapping"],
    image_sizes=inputs["image_sizes"])
print(points)  # [{object_id, image_num, x, y}]
```

Detailed model issues and environment matrices: see [references/issues.md](references/issues.md).

## Resources

- Qwen3.6-27B HF: https://huggingface.co/Qwen/Qwen3.6-27B (Apache-2.0; released 2026-04-22)
- Qwen3.6-35B-A3B HF: https://huggingface.co/Qwen/Qwen3.6-35B-A3B (Apache-2.0; released 2026-04-16)
- Qwen3.6 GitHub: https://github.com/QwenLM/Qwen3.6 (includes vLLM/SGLang deployment recipes)
- Qwen3.5-397B-A17B HF: https://huggingface.co/Qwen/Qwen3.5-397B-A17B (Feb 2026; unified multimodal, no -VL)
- Qwen3-VL-8B-Instruct (legacy): https://huggingface.co/Qwen/Qwen3-VL-8B-Instruct (still real; Oct 2025)
- Qwen3-VL-32B-Instruct (legacy): https://huggingface.co/Qwen/Qwen3-VL-32B-Instruct (still real; Oct 2025)
- vLLM: https://github.com/vllm-project/vllm (>=0.19.0 for Qwen3.6; >=0.12.0 for structured_outputs)
- InternVL3.5-14B: https://huggingface.co/OpenGVLab/InternVL3_5-14B (released 2025-08-26)
- SpatialRGPT: https://github.com/AnjieCheng/SpatialRGPT (Apache-2.0; NeurIPS 2024)
- SpatialBot-3B: https://huggingface.co/RussRobin/SpatialBot-3B
- MolmoPoint-8B: https://huggingface.co/allenai/MolmoPoint-8B (Apache-2.0; released 2026-03-18)
- Qwen2.5-VL-72B-AWQ: https://huggingface.co/Qwen/Qwen2.5-VL-72B-Instruct-AWQ (Qwen license, legacy)

Operational rule: VLMs propose semantic label, candidate joint type, axis anchor, evidence, counterevidence, uncertainty. Geometry decides final joint type, axis, range, and simulation-ready URDF parameters.
