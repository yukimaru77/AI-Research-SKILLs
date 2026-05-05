---
name: kinematic-json-constrained-decode
description: Forces VLMs and LLMs to emit strict kinematic JSON for lab-equipment joint prediction using OpenAI Structured Outputs, Anthropic strict tool use, vLLM XGrammar guided decoding, Outlines, llguidance, Instructor, and Pydantic. Use when a downstream consumer (URDF authoring, robot control, simulator, VR digital twin) parses the model output and malformed JSON or non-physical values are unacceptable. Treats schema conformance as necessary but not sufficient; pairs constrained decoding with Pydantic validators and a repair loop for degrees-vs-radians, axis sign, range bounds, and joint-type-specific invariants.
version: 2.0.0
author: Orchestra Research
license: MIT
tags: [Constrained Decoding, JSON Schema, Pydantic, Instructor, Outlines, XGrammar, LLGuidance, vLLM, Structured Outputs, OpenAI, Anthropic, Kinematic JSON, URDF, Affordance, VLM]
dependencies: [pydantic==2.13.3, instructor==1.15.1, outlines==1.2.13, xgrammar==0.2.0, llguidance==1.7.5, openai==2.34.0, anthropic==0.98.0, vllm==0.20.1]
---

# Kinematic JSON Constrained Decoding

Pipeline position: video → camera poses → 3DGS → cluster moving parts → **VLM affordance (this skill)** → URDF/physics → VR rendering.

This skill enforces grammar-level JSON structure at token generation time, then applies a Pydantic physics layer to catch unit errors and kinematic invariant violations that structure alone cannot prevent.

## Quick start

```bash
pip install "pydantic==2.13.3" "instructor==1.15.1" "outlines==1.2.13" \
            "xgrammar==0.2.0" "llguidance==1.7.5" \
            "openai==2.34.0" "anthropic==0.98.0"

# vLLM separately (CUDA/driver constraints)
pip install "vllm==0.20.1"
# or: docker pull vllm/vllm-openai:v0.20.1
```

Public contract consumed by downstream URDF/sim/VR:

```json
{
  "joint_id": "centrifuge_lid_hinge",
  "joint_type": "revolute",
  "parent_link": "centrifuge_body",
  "child_link": "centrifuge_lid",
  "origin_m": {"x": 0.12, "y": -0.04, "z": 0.31},
  "axis_unit": {"x": 0.0, "y": 1.0, "z": 0.0},
  "limit_lower": 0.0,
  "limit_upper": 1.658,
  "limit_units": "rad",
  "evidence": ["rear hinge knuckles visible in side view"],
  "confidence": 0.87
}
```

## VLM selection (May 2026)

**Canonical local VLM for visual JSON / affordance extraction on vLLM:**

| Model | HF ID | Status |
|---|---|---|
| **Qwen3.6 27B** | `Qwen/Qwen3.6-27B` | **Current canonical (Apr 2026)**; unified vision model, Apache-2.0; requires `transformers>=4.57.1` / `vllm>=0.19.0` |
| Qwen3.5 27B | `Qwen/Qwen3.5-27B` | Predecessor; pin deps and run schema tests — vLLM #38696 (garbled-whitespace JSON) open as of May 2026 |
| Qwen3-VL 8B/32B | `Qwen/Qwen3-VL-*-Instruct` | Legacy/baseline (Oct 2025); valid for low-resource or comparison runs |
| Molmo2 / MolmoPoint | AllenAI family | Grounding/pointing specialist; use when spatial pointing matters more than schema extraction |
| InternVL3.5 | `OpenGVLab/InternVL3_5-*` | Strong alternative; benchmark against Qwen3.6 |
| Llama 4 Scout/Maverick | `meta-llama/Llama-4-*` | General multimodal; less canonical for constrained JSON on vLLM |

**Migration notes:**
- `Qwen/Qwen2.5-VL-7B-Instruct` — superseded; migrate to Qwen3.6-27B for new work.
- No `Qwen3.5-VL-*` suffix exists. Qwen3.5/3.6 use unified `Qwen/Qwen3.*` IDs (text + vision, not a separate VL branch).
- vLLM #38696: garbled-whitespace JSON with Qwen3.5; prefer Qwen3.6 until resolved.

## Package matrix

| Package | Version | License | Role |
|---|---|---|---|
| pydantic | 2.13.3 | MIT | Schema, validation, physics invariants |
| instructor | 1.15.1 | MIT | Retry-on-validation, provider adapters |
| outlines | 1.2.13 | Apache-2.0 | Local constrained generation via `from_transformers` |
| xgrammar | 0.2.0 | Apache-2.0 | Grammar engine; default vLLM structured-output backend |
| llguidance | 1.7.5 | MIT | Alternative grammar engine; JSON Schema/Lark CFG |
| openai SDK | 2.34.0 | Apache-2.0 | OpenAI Structured Outputs (`json_schema` strict) |
| anthropic SDK | 0.98.0 | MIT | Claude strict tool use with grammar-cache warmup |
| vLLM | 0.20.1 | Apache-2.0 | Local serving with `--structured-outputs-config.backend` |
| lm-format-enforcer | 0.11.3 | MIT | Transformers logits-level fallback (legacy path) |
| guidance | 0.3.1 | MIT | Programmatic grammar model; alternative vLLM backend |

Note: `guided_json`, `guided_regex`, `guided_choice`, `guided_decoding_backend`, and related legacy vLLM fields were **removed in v0.12.0**. Use `StructuredOutputsParams` and `--structured-outputs-config.backend` exclusively.

## Pydantic schema

Conservative schema for all strict-output providers. Avoids `minimum`, `maximum`, `minItems`, `defaults`, and `format` in the provider-facing JSON Schema; those are enforced post-generation by Pydantic validators.

```python
# schemas/joint_spec.py
from __future__ import annotations
from enum import Enum
from math import isfinite, sqrt
from typing import Literal
from pydantic import BaseModel, ConfigDict, Field, ValidationError, field_validator, model_validator

class JointType(str, Enum):
    revolute = "revolute"
    prismatic = "prismatic"
    fixed = "fixed"

class Vec3(BaseModel):
    model_config = ConfigDict(extra="forbid")
    x: float
    y: float
    z: float

    def norm(self) -> float:
        return sqrt(self.x**2 + self.y**2 + self.z**2)

    @model_validator(mode="after")
    def finite_components(self) -> "Vec3":
        if not all(isfinite(v) for v in (self.x, self.y, self.z)):
            raise ValueError("Vector components must be finite.")
        return self

class JointSpec(BaseModel):
    model_config = ConfigDict(extra="forbid")
    joint_id: str
    joint_type: JointType
    parent_link: str
    child_link: str
    origin_m: Vec3                          # meters, parent frame
    axis_unit: Vec3                         # unit vector (0,0,0 for fixed)
    limit_lower: float | None = Field(...)  # rad (revolute), m (prismatic), null (fixed)
    limit_upper: float | None = Field(...)
    limit_units: Literal["rad", "m", "none"]
    evidence: list[str]                     # 1-6 short visual evidence strings
    confidence: float                       # [0.0, 1.0]

    @field_validator("confidence")
    @classmethod
    def confidence_range(cls, v: float) -> float:
        if not 0.0 <= v <= 1.0:
            raise ValueError("confidence must be in [0.0, 1.0]")
        return v

    @field_validator("evidence")
    @classmethod
    def evidence_nonempty(cls, v: list[str]) -> list[str]:
        if not 1 <= len(v) <= 6:
            raise ValueError("evidence must contain 1-6 items")
        if any(len(s.strip()) == 0 for s in v):
            raise ValueError("evidence items must be non-empty strings")
        return v

    @model_validator(mode="after")
    def physics_consistency(self) -> "JointSpec":
        norm = self.axis_unit.norm()
        if self.joint_type == JointType.fixed:
            if self.limit_units != "none":
                raise ValueError("fixed joints must use limit_units='none'")
            if self.limit_lower is not None or self.limit_upper is not None:
                raise ValueError("fixed joints must have null limits")
            if norm > 1e-6:
                raise ValueError("fixed joints must use axis_unit=(0,0,0)")
            return self
        if not 0.95 <= norm <= 1.05:
            raise ValueError("revolute/prismatic axis_unit must be unit length")
        expected = "rad" if self.joint_type == JointType.revolute else "m"
        if self.limit_units != expected:
            raise ValueError(f"{self.joint_type.value} requires limit_units={expected!r}")
        if self.limit_lower is not None and self.limit_upper is not None:
            if self.limit_lower > self.limit_upper:
                raise ValueError("limit_lower must be <= limit_upper")
        return self

def provider_json_schema(model_cls=JointSpec) -> dict:
    """Strip defaults, ensure additionalProperties:false recursively."""
    schema = model_cls.model_json_schema()
    def walk(node):
        if isinstance(node, dict):
            if node.get("type") == "object":
                node["additionalProperties"] = False
            node.pop("default", None)
            for v in node.values():
                walk(v)
        elif isinstance(node, list):
            for v in node:
                walk(v)
    walk(schema)
    return schema
```

## Common workflows

### Workflow 1: OpenAI GPT (Structured Outputs)

```
- [ ] Build provider_json_schema(JointSpec)
- [ ] Prompt with explicit unit rules: radians, meters, unit vectors
- [ ] Send response_format={"type":"json_schema","json_schema":{...,"strict":True}}
- [ ] Revalidate locally with JointSpec.model_validate_json()
- [ ] On ValidationError: inject errors and retry (max 3)
```

```python
from openai import OpenAI
from pydantic import ValidationError

SYSTEM = (
    "Emit exactly one JointSpec JSON. SI units only: radians for revolute, "
    "meters for prismatic and origins. Never output degrees or millimeters. "
    "Convert before output: 95° = 1.658 rad, 180 mm = 0.180 m."
)

def predict_openai(image_urls: list[str], model="gpt-4o-mini", max_attempts=3):
    client = OpenAI()
    schema = provider_json_schema()
    fmt = {"type": "json_schema", "json_schema": {"name": "JointSpec", "strict": True, "schema": schema}}
    content = [{"type": "text", "text": "Infer the dominant joint. Parent frame: meters."}]
    content += [{"type": "image_url", "image_url": {"url": u}} for u in image_urls]
    messages = [{"role": "system", "content": SYSTEM}, {"role": "user", "content": content}]
    for _ in range(max_attempts):
        raw = client.chat.completions.create(
            model=model, temperature=0, max_tokens=700,
            messages=messages, response_format=fmt,
        ).choices[0].message.content or ""
        try:
            return JointSpec.model_validate_json(raw)
        except ValidationError as exc:
            messages += [{"role": "assistant", "content": raw},
                         {"role": "user", "content": f"Fix validation errors:\n{exc.errors()}"}]
    raise RuntimeError("OpenAI structured output failed after retries")
```

Optional Instructor wrapper:

```python
import instructor
client = instructor.from_openai(OpenAI(), mode=instructor.Mode.JSON_SCHEMA)
spec = client.chat.completions.create(
    model="gpt-4o-mini", messages=[...], response_model=JointSpec, max_retries=2)
```

### Workflow 2: Anthropic Claude strict tool use

```
- [ ] Register tool with strict=True and input_schema=provider_json_schema()
- [ ] Warm grammar cache once per worker (first call compiles + caches up to 24 h)
- [ ] Keep tool name/schema/strict identical across all production calls
- [ ] Force tool_choice={"type":"tool","name":"emit_joint_spec"}
- [ ] Validate tool_use.input with JointSpec.model_validate()
- [ ] On ValidationError: inject errors and retry
```

```python
from anthropic import Anthropic
from pydantic import ValidationError

TOOL = {
    "name": "emit_joint_spec",
    "description": "Emit exactly one kinematic JointSpec for lab-equipment digital-twin modeling.",
    "strict": True,
    "input_schema": provider_json_schema(),
}

def predict_claude(image_blocks: list, model="claude-sonnet-4-5", max_attempts=3):
    client = Anthropic()
    # Grammar warmup: compile-and-cache on first call, reuse for 24 h
    client.messages.create(
        model=model, max_tokens=256, tools=[TOOL],
        tool_choice={"type": "tool", "name": "emit_joint_spec"},
        messages=[{"role": "user", "content": "Warm grammar. Return fixed placeholder for locked bracket."}],
    )
    msgs = [{"role": "user", "content": [
        {"type": "text", "text": "Infer joint. Radians for revolute, meters for prismatic. Use emit_joint_spec."},
    ] + image_blocks}]
    for _ in range(max_attempts):
        resp = client.messages.create(
            model=model, max_tokens=800, temperature=0,
            tools=[TOOL], tool_choice={"type": "tool", "name": "emit_joint_spec"}, messages=msgs)
        raw = next(b.input for b in resp.content if getattr(b, "type", None) == "tool_use")
        try:
            return JointSpec.model_validate(raw)
        except ValidationError as exc:
            msgs += [{"role": "assistant", "content": str(raw)},
                     {"role": "user", "content": f"Repair tool input. Errors: {exc.errors()}"}]
    raise RuntimeError("Claude validation failed after retries")
```

Cache behavior: schema structure change → cache miss; tool name/description change only → cache hit. Never mutate `input_schema` between requests.

### Workflow 3: Local vLLM + XGrammar (A100 / Docker)

```
- [ ] Serve model with --structured-outputs-config.backend xgrammar
- [ ] Pass response_format as top-level OpenAI-compatible parameter (NOT in extra_body)
- [ ] Validate with Pydantic locally regardless
- [ ] Run startup canary before accepting traffic
- [ ] Fall back to --structured-outputs-config.backend auto on tokenizer mismatch
```

```bash
# Server (vLLM 0.20.1) — Qwen3.6-27B is the current canonical VLM (Apr 2026)
vllm serve Qwen/Qwen3.6-27B \
  --host 0.0.0.0 --port 8000 \
  --structured-outputs-config.backend xgrammar

# Docker equivalent
docker run --gpus all --ipc=host -p 8000:8000 \
  vllm/vllm-openai:v0.20.1 \
  --model Qwen/Qwen3.6-27B \
  --structured-outputs-config.backend xgrammar
```

```python
from openai import OpenAI

def predict_local(image_urls: list[str], base_url="http://localhost:8000/v1",
                  model="Qwen/Qwen3.6-27B"):
    client = OpenAI(base_url=base_url, api_key="EMPTY")
    schema = provider_json_schema()
    content = [{"type": "text", "text": "Infer one JointSpec. Radians, meters, unit vectors only."}]
    content += [{"type": "image_url", "image_url": {"url": u}} for u in image_urls]
    resp = client.chat.completions.create(
        model=model, temperature=0, max_tokens=700,
        response_format={"type": "json_schema", "json_schema": {"name": "JointSpec", "schema": schema}},
        messages=[{"role": "system", "content": "Precise kinematic JSON predictor."},
                  {"role": "user", "content": content}],
    )
    return JointSpec.model_validate_json(resp.choices[0].message.content)

# Offline vLLM (batch)
from vllm import LLM, SamplingParams
from vllm.sampling_params import StructuredOutputsParams

llm = LLM(model="Qwen/Qwen3.6-27B")
sampling_params = SamplingParams(
    temperature=0.0, max_tokens=800,
    structured_outputs=StructuredOutputsParams(json=provider_json_schema()),
)
```

**Outlines alternative (local, no server):**

```python
import outlines
from transformers import AutoModelForCausalLM, AutoTokenizer

hf_id = "Qwen/Qwen3.6-27B"
model = outlines.from_transformers(
    AutoModelForCausalLM.from_pretrained(hf_id, device_map="auto"),
    AutoTokenizer.from_pretrained(hf_id),
)
raw = model("Infer one JointSpec for a centrifuge lid hinge. Radians, meters.", JointSpec, max_tokens=800)
spec = raw if isinstance(raw, JointSpec) else JointSpec.model_validate_json(raw)
```

## Provider-neutral repair loop

Constrained decoding enforces structure. Pydantic enforces physics. The repair loop connects them.

```python
from pydantic import ValidationError

REPAIR_SUFFIX = (
    "\n\nPrevious JointSpec failed Pydantic/physics validation. Fix ONLY schema, units, "
    "and kinematic consistency. Do not invent new visual evidence.\n"
    "Key rules: revolute→radians, prismatic→meters, fixed→null limits + axis (0,0,0).\n"
    "Validation errors:\n{errors}\n\nPrevious JSON:\n{raw}"
)

def repair_until_valid(*, messages: list, generate_fn, max_attempts=3) -> JointSpec:
    last_raw = ""
    for _ in range(max_attempts):
        last_raw = generate_fn(messages)
        try:
            return JointSpec.model_validate_json(last_raw)
        except ValidationError as exc:
            messages += [
                {"role": "assistant", "content": last_raw},
                {"role": "user", "content": REPAIR_SUFFIX.format(
                    errors=exc.errors(), raw=last_raw[:500])},
            ]
    raise RuntimeError(f"Repair failed. Last={last_raw[:500]}")
```

## When to use vs alternatives

**Use this skill when:** output is parsed by code (URDF, sim, VR, dataset); predictions must be comparable across providers; deterministic failure on malformed JSON is required; VLM is strong at visual semantics but weak at formatting.

**Prefer plain JSON mode when:** output is human-inspected, occasional malformed JSON is acceptable, schema is unstable.

**Prefer tool calling without strict mode when:** model must call downstream functions and traces matter more than schema enforcement.

**Prefer geometry pipeline when:** CAD/URDF/STEP/depth already provides the joint and sub-mm accuracy matters.

**Prefer post-hoc repair only when:** the backend cannot enforce schema (legacy model) and robust validators are in place.

## Common issues

### OpenAI strict mode rejects schema (400 error)

Symptom: `400 invalid_request_error ... not strict` or `additionalProperties must be false`. Fix: run `provider_json_schema()` — sets `additionalProperties:false` recursively, removes defaults, lists all fields as `required`. Use `extra="forbid"` not `extra="allow"` (openai-python #2740, #1659, #2024/PR#2025).

### OpenAI rejects Pydantic constraint keywords

Symptom: `Unsupported schema keyword: minItems / minimum / pattern`. Fix: keep provider-facing schema simple; enforce lengths, ranges, and unit checks in Pydantic validators post-generation only.

### Instructor retry not propagating errors correctly

Symptom: `ValidationError` raised but retry prompt lacks useful error text; retries exhaust without improvement.

Fix: pin `instructor==1.15.1`; retry behavior changed across 1.11.3 (attempt tracking), 1.13.0 (JSON decode retry), 1.14.0 (provider exception standardization), 1.14.4 (Responses API ValidationError), 1.15.1 (attempt metadata in hooks). No confirmed 2.x stable as of May 2026. Keep `repair_until_valid` as manual fallback for regression tests.

### Outlines API — `from_transformers` vs `generate.json`

Current README style prefers `outlines.from_transformers(model, tokenizer)` and direct typed calls `model(prompt, JointSpec)`. The older `generate.json(model, JointSpec)` style is still present in reference docs; no formal deprecation confirmed, but smoke-test both paths against your backend (Outlines #1083: JSON Schema pattern disagreement; #1325: additionalProperties boolean issue with vLLM guided-decoding backend).

### XGrammar tokenizer vocab_size mismatch

Symptom: `xgrammar assertion failure`, `ValueError: input vocab_size … less than minimum viable`.

Fix: keep vLLM and xgrammar pinned together; test every VLM tokenizer pair at startup. vLLM #14534 (PR #14823, merged 2025-03-14). vLLM #13038: JSON schema not honored with Qwen2.5-VL — resolved by migrating to Qwen3.6-27B. If mismatch persists, fall back to `--structured-outputs-config.backend auto`.

### XGrammar logits dtype error (CPU / macOS path)

Symptom: `ValueError: logits must be float32` or dtype mismatch on CPU kernel. Fix: vLLM 0.20.1 includes PR #32384 (merged 2026-03-14) converting logits to float32 for the CPU mask path. On A100 Docker, prefer CUDA; keep `backend auto` as fallback.

### XGrammar bitmask index type (vLLM Ascend / scheduling changes)

Symptom: `apply_token_bitmask_inplace_cpu` receives `torch.Tensor` where `List[int]` expected. Fix: vllm-ascend PR #6151 (merged 2026-01-23); requires `xgrammar>=0.1.30`. Not hit on standard CUDA.

### Qwen3.5 garbled-whitespace JSON output (vLLM #38696)

Symptom: Qwen3.5 generates JSON with spurious whitespace or incomplete tokens even with XGrammar backend. Fix: open issue as of May 2026. Use Pydantic repair loop and `backend auto`. Prefer Qwen3.6-27B for production until resolved.

### XGrammar crash with Llama 4 Maverick FP8

Symptom: guided JSON crashes or enters whitespace loop (vLLM #18085).

Fix: no merged fix as of May 2026. Use model-specific smoke tests and `backend auto` fallback.

### Claude grammar cache miss on first request after deploy

Symptom: first strict tool-use request is slow (grammar compile). Fix: warm once per worker at startup with identical tool name, schema, and `strict:True`. Structure change → cache miss; name/description change only → cache hit. Cache persists up to 24 hours.

### vLLM ignores response_format

Symptom: model emits prose instead of JSON. Fix: pass `response_format` as a top-level OpenAI-compatible parameter — never in `extra_body`. Confirm the model supports structured outputs; run startup canary.

## Advanced topics

### Startup canary

Run before accepting traffic on every serving process:

```python
def canary(predict_fn):
    spec = predict_fn([""], observation="A fixed aluminum bracket. No DOF.")
    assert spec.joint_type == JointType.fixed
    assert spec.limit_units == "none"
    assert spec.limit_lower is None
    assert spec.limit_upper is None
```

### Schema hash for cache invalidation

```python
import hashlib, json
schema_hash = hashlib.sha256(
    json.dumps(provider_json_schema(), sort_keys=True).encode()
).hexdigest()
```

### Production logging fields

`provider`, `model`, `schema_hash`, `structured_backend`, `raw_json`, `validated_json`, `confidence`, `limit_units`, `joint_type`, `latency_ms`, `repair_attempts`, `failure_reasons`.

### Regression fixtures

| Fixture | Expected joint_type | limit_units |
|---|---|---|
| `centrifuge_lid_hinge` | revolute | rad |
| `pipette_tip_box_lid` | revolute | rad |
| `drawer_slide_in_balance` | prismatic | m |
| `fixed_microscope_stage_adapter` | fixed | none |

### Common physical pitfalls

- **Degrees vs radians.** Models output `90` for revolute. Repair: "Revolute ranges must be radians. 95 deg = 1.658 rad."
- **Meters vs millimeters.** Slider `180` means mm. Repair: "Prismatic ranges are meters. 180 mm = 0.180 m."
- **Axis sign ambiguity.** `axis` and `-axis` are equivalent. Pick canonical sign for your downstream frame.
- **Free-floating joints.** Schema is single-axis; 6-DoF free joints require special handling outside this schema.
- **Coordinate-frame drift.** Every prompt must state the output frame. Never mix pixel anchors with metric 3D.

Detailed provider issue links and regression test recipes: see [references/issues.md](references/issues.md).

## Resources

- Pydantic 2.x: https://github.com/pydantic/pydantic
- Instructor: https://github.com/instructor-ai/instructor
- Outlines: https://github.com/dottxt-ai/outlines
- XGrammar: https://github.com/mlc-ai/xgrammar
- llguidance: https://github.com/guidance-ai/llguidance
- Guidance: https://github.com/guidance-ai/guidance
- lm-format-enforcer: https://github.com/noamgat/lm-format-enforcer
- OpenAI Structured Outputs: https://platform.openai.com/docs/guides/structured-outputs
- Anthropic strict tool use: https://docs.anthropic.com/en/docs/agents-and-tools/tool-use/overview
- vLLM structured outputs: https://docs.vllm.ai/en/stable/features/structured_outputs.html
- Qwen3.6-27B (canonical Apr 2026): https://huggingface.co/Qwen/Qwen3.6-27B — lineage: Qwen3-VL (Oct 2025, legacy) → Qwen3.5 → Qwen3.6 (current)
