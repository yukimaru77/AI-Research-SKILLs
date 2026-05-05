# Multi-server routing

Decision logic for choosing which server to dispatch a worker on. The agent decides directly — no `deep_thinker` mediation needed for routine routing.

## Decision tree

```
Does this experiment need >40 GB VRAM (or >per-device-VRAM on the multi-GPU server)?
├── Yes → Multi-GPU server (with FSDP/DeepSpeed/Megatron/vLLM-TP) OR single big-VRAM server
│         ↓
│   Does the library have mature multi-GPU support?
│   ├── Yes → Multi-GPU server (uses several devices, e.g. FSDP)
│   └── No  → Single big-VRAM server (vanilla model.cuda())
│
└── No → Either server works
          ↓
   Are you running ≥ 4 parallel hyperparameter configs concurrently?
   ├── Yes → Multi-GPU server (one config per device)
   └── No  → Either; default to multi-GPU server unless single-GPU server is idle
```

## Routine cases

| Scenario | Pick | Why |
|---|---|---|
| Bring-Up reproduction (small model, well-known repo) | Multi-GPU server | Plenty of devices, doesn't need the big VRAM |
| Hyperparameter sweep, K configs, each fits in per-device-VRAM | Multi-GPU server | One config per device |
| Distributed training (FSDP/DeepSpeed) on a 70 B model | Multi-GPU server | Total VRAM matters |
| Inference benchmark with vLLM tensor-parallel | Multi-GPU server | TP across devices |
| Single-experiment fine-tune of a 13 B model with HF Trainer + DDP | Multi-GPU server | DDP works fine across A100s |
| Single big VLM (Qwen2-VL-72B etc.) inference at 2k+ context | Single big-VRAM server | Vanilla model.cuda() gets 144 GB |
| Research code with no obvious multi-GPU adapter | Single big-VRAM server | Avoid distributed-training hell |
| Pre-RLHF reward model that needs huge batch | Single big-VRAM server | One device, huge batch |
| Quick smoke test / sanity check | Multi-GPU server | Just grab device 0 |

## Why "multi-GPU server has more total VRAM" is misleading

A multi-GPU server with 8 × 40 GB has 320 GB of *aggregate* VRAM. But:

- A single Python process running a vanilla `model.cuda()` only sees the device it's pinned to — 40 GB, not 320.
- To realize the 320 GB, you must use a library that **shards** model weights / activations / optimizer state across devices: FSDP, DeepSpeed, Megatron-LM, vLLM tensor-parallel, etc.
- These libraries require the model to be sharding-friendly (Transformer-shaped, attention dimensions divisible by TP degree, etc.) and the training code to be rank-aware.
- If your code isn't sharding-aware, the 320 GB is fictional.

The single big-VRAM server bypasses this entirely. 144 GB is yours, no NCCL, no rank coordination, no FSDP wrapper, no `mesh_dim`. For experiments where the library lacks well-tested multi-GPU support — or where you want the simplest possible training loop — the single big-VRAM server is the right answer.

## When to deliberately split work across servers

| Situation | Strategy |
|---|---|
| Long single-model training + parallel ablation sweep | Big-VRAM server runs the main model; multi-GPU server runs sweep workers |
| Inference benchmarking (one big model) + data preprocessing (CPU-bound) | Big-VRAM server runs inference; orchestrator (multi-GPU host) runs CPU prep on a small worker |
| Reproducing a published paper that requires both N-GPU training and 1-GPU long-context eval | Multi-GPU server for training, single big-VRAM for eval |

## Encoding the choice in `research-state.yaml`

The agent should record its routing rationale alongside the experiment, so future sessions can audit and improve the policy:

```yaml
experiments:
  - slug: H1_baseline_repro
    server: saitou
    gpus_used: 1
    routing_reason: "Bring-Up reproduction; fits in 40 GB; no need for h200"
    bringup_baseline_ref: gsplat
  - slug: H4_long_context_qwen
    server: saitou-h200
    gpus_used: 1
    routing_reason: "Qwen2-VL-72B at 16k context needs >40 GB; vLLM TP not yet validated for this model"
```

Auditing these entries periodically reveals systematic mistakes (e.g., always defaulting to one server out of habit).

## Common mistakes

- **Routing every experiment to one server**: leaves the other idle. Spread the load when both are options.
- **Picking multi-GPU server for a single-GPU experiment requiring >40 GB**: vanilla `model.cuda()` will OOM on every device. Use the big-VRAM server.
- **Picking single big-VRAM server for parallel sweeps**: wastes the parallelism opportunity. Multi-GPU server can run K configs in parallel.
- **Forgetting that NFS workspace is shared**: experiments dispatched to the remote server still write to the same workspace; results show up automatically. Don't `scp` or `rsync` unless you mean to.
