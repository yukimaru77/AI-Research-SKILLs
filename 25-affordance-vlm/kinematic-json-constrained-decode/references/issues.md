# Constrained Decoding Issues and Tested Versions

Maintain alongside SKILL.md as a tested issue/version log per provider.

## OpenAI

- Strict mode requires `additionalProperties: false` and all fields `required`.
- Track provider-specific unsupported JSON Schema keywords (`minimum`, `maximum`, `minItems`, `pattern`, `format`, ...).
- Real OpenAI Python issue: 400 response until `strict: true` and `additionalProperties: false` added.
- Regression prompt set: fixed bracket, centrifuge hinge, pipette drawer rail.

```python
schema = force_strict_objects(strip_nonportable_keywords(JointSpec.model_json_schema()))
response_format = {"type": "json_schema",
                   "json_schema": {"name": "JointSpec", "strict": True, "schema": schema}}
```

## Anthropic

- Strict tool schema: grammar compiles on first use, caches 24h from last use.
- Schema/tool changes invalidate cache; changing only `name`/`description` does NOT invalidate.
- Warm cache on worker startup using the EXACT TOOL object that production uses.
- Track cold-start latency; expect it on first request after deploy or schema change.
- Reference: https://docs.anthropic.com/en/docs/agents-and-tools/tool-use/overview

## Instructor

- Pin `instructor==1.15.1`.
- Test `max_retries` in CI: validate that ValidationError is fed back as useful error text.
- Test OpenAI `Mode.JSON_SCHEMA` and Anthropic `Mode.ANTHROPIC_TOOLS`.
- Preserve raw responses for incident triage.
- Known: 1.x retry semantics have changed across releases; some validation exceptions were not fed back as expected.

## Outlines

- Pin `outlines==1.2.12`.
- Prefer `from outlines import models, generate; generate.json(model, PydanticModel)`.
- Avoid low-level `outlines.grammars.json` unless explicitly tested.
- Compatibility shim for older `outlines.from_transformers` codepaths is provided in SKILL.md.
- 1.x API surface evolved; example code from older docs may not import cleanly.

## vLLM / xgrammar

- Pin xgrammar==0.1.34 in production; test 0.2.0 (released 2026-05-01) separately.
- Pin tokenizer revision alongside model revision; do NOT mix HF tokenizer revs with vLLM weights.
- Smoke-test structured output at server boot with a known JointSpec canary.
- Backend fallback matrix: `xgrammar` -> `guidance` (llguidance) -> `outlines` -> post-hoc repair.
- Known issues: xgrammar tokenizer assertion failures, vocab_size mismatch, mask shape mismatch, dtype errors (`logits must be float32`), function-argument mismatches.
- Use `--structured-outputs-config.backend auto` as a fallback launch option.

```bash
vllm serve Qwen/Qwen3-VL-8B-Instruct \
  --served-model-name qwen3-vl --trust-remote-code \
  --structured-outputs-config.backend xgrammar
# or fallback:
#   --structured-outputs-config.backend auto
# Legacy flag:
#   --guided-decoding-backend xgrammar
```

## Provider-ignores-response_format

vLLM / Qwen issue: model emits prose instead of JSON when `response_format` is buried in `extra_body` on incompatible versions. Fix: pass as TOP-LEVEL OpenAI-compatible parameter.

```python
# Good
client.chat.completions.create(model="qwen3-vl", messages=messages,
                               response_format=JOINT_SPEC_RESPONSE_FORMAT)
# Risky
client.chat.completions.create(model="qwen3-vl", messages=messages,
                               extra_body={"response_format": JOINT_SPEC_RESPONSE_FORMAT})
```

## Kinematics conventions

- Dataset unit convention: meters for anchor; radians for revolute range; meters for prismatic range.
- Axis sign convention: lexicographically positive (canonical_axis_sign in SKILL.md).
- Coordinate frame must be stated explicitly in every prompt: camera frame, robot base frame, object canonical frame, or CAD frame.
- Free-joint sentinel policy: `range == [0, 0]`, axis `[0, 0, 1]`, internal `failure_reasons += "free_joint_not_representable_as_single_axis"`.
- Physical validator thresholds: axis norm tolerance `1e-3`; range monotonic `lo <= hi`; revolute range outside `[-2pi, 2pi]` flagged as suspicious.

## Production logging fields

- provider, model, model_revision, tokenizer_revision
- schema_hash (SHA-256 of canonicalized JSON Schema)
- structured_backend (xgrammar / outlines / openai_strict / anthropic_tools)
- raw_json, validated_json
- validator_score, failure_reasons
- latency_ms, evidence_view_ids

## Regression fixtures

```json
[
  {"name": "centrifuge_lid_hinge", "expected_joint_type": "revolute", "range_units": "radians", "verbs": ["open", "close"]},
  {"name": "pipette_tip_box_lid", "expected_joint_type": "revolute", "range_units": "radians", "verbs": ["open", "close"]},
  {"name": "drawer_slide_in_balance", "expected_joint_type": "prismatic", "range_units": "meters", "verbs": ["pull", "push", "slide"]},
  {"name": "fixed_microscope_stage_adapter", "expected_joint_type": "fixed", "range": [0, 0], "verbs": []}
]
```

## Startup canary

```python
def canary(predict_fn):
    spec = predict_fn("A fixed aluminum bracket bolted to an optical table. Cannot rotate or slide. Emit JointSpec JSON.")
    assert spec.joint_type == "fixed"
    assert spec.range == [0.0, 0.0]
    assert abs(sum(x*x for x in spec.axis) - 1.0) < 1e-3
```
