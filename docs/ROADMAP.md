# 🗺️ Roadmap

## Vision

Build the most comprehensive open-source library of AI research skills, enabling AI agents to autonomously conduct experiments from hypothesis to deployment.

**Target**: 86 comprehensive skills — achieved ✅ | **134 skills achieved (May 2026) ✅**

## Progress Overview

| Metric | Current | Target |
|--------|---------|--------|
| **Skills** | **134** (high-quality, standardized YAML) | 86 ✅ → 134 ✅ |
| **Avg Lines/Skill** | **420 lines** (focused + progressive disclosure) | 200-500 lines |
| **Documentation** | **~150,000 lines** total (SKILL.md + references) | 100,000+ lines |
| **Gold Standard Skills** | **65** with comprehensive references | 50+ ✅ |
| **Coverage** | Autoresearch, Ideation, Paper Writing, Architecture, Tokenization, Fine-Tuning, Data Processing, Post-Training, Safety, Distributed, Infrastructure, Optimization, Evaluation, Inference, Agents, RAG, Multimodal, MLOps, Observability, Prompt Engineering, Emerging Techniques, **3D Reconstruction, 3D Segmentation & Articulation, Affordance VLM, 3D Rendering & VR, Physics Simulation, Digital Twin Workflows** | Full Lifecycle ✅ |

## Development Phases

### ✅ Phase 1: Model Architecture (COMPLETE - 5 skills)
**Status**: Core model architectures covered

**Completed Skills**:
- ✅ **Megatron-Core** - NVIDIA's framework for training 2B-462B param models
- ✅ **LitGPT** - Lightning AI's 20+ clean LLM implementations
- ✅ **Mamba** - State-space models with O(n) complexity
- ✅ **RWKV** - RNN+Transformer hybrid, infinite context
- ✅ **NanoGPT** - Educational GPT in ~300 lines by Karpathy

### ✅ Phase 2: Tokenization (COMPLETE - 2 skills)
**Status**: Essential tokenization frameworks covered

**Completed Skills**:
- ✅ **HuggingFace Tokenizers** - Rust-based, BPE/WordPiece/Unigram
- ✅ **SentencePiece** - Language-independent tokenization

### ✅ Phase 3: Fine-Tuning (COMPLETE - 4 skills)
**Status**: Core fine-tuning frameworks covered

**Completed Skills**:
- ✅ **Axolotl** - YAML-based fine-tuning with 100+ models
- ✅ **LLaMA-Factory** - WebUI no-code fine-tuning
- ✅ **Unsloth** - 2x faster QLoRA fine-tuning
- ✅ **PEFT** - Parameter-efficient fine-tuning with LoRA, QLoRA, DoRA, 25+ methods

### ✅ Phase 4: Data Processing (COMPLETE - 2 skills)
**Status**: Distributed data processing covered

**Completed Skills**:
- ✅ **Ray Data** - Distributed ML data processing
- ✅ **NeMo Curator** - GPU-accelerated data curation

### ✅ Phase 5: Post-Training (COMPLETE - 4 skills)
**Status**: RLHF and alignment techniques covered

**Completed Skills**:
- ✅ **TRL Fine-Tuning** - Transformer Reinforcement Learning
- ✅ **GRPO-RL-Training** - Group Relative Policy Optimization (gold standard)
- ✅ **OpenRLHF** - Full RLHF pipeline with Ray + vLLM
- ✅ **SimPO** - Simple Preference Optimization

### ✅ Phase 6: Safety & Alignment (COMPLETE - 4 skills)
**Status**: Core safety frameworks covered

**Completed Skills**:
- ✅ **Constitutional AI** - AI-driven self-improvement via principles
- ✅ **LlamaGuard** - Safety classifier for LLM inputs/outputs
- ✅ **NeMo Guardrails** - Programmable guardrails with Colang
- ✅ **Prompt Guard** - Meta's 86M prompt injection & jailbreak detector

### ✅ Phase 7: Distributed Training (COMPLETE - 5 skills)
**Status**: Major distributed training frameworks covered

**Completed Skills**:
- ✅ **DeepSpeed** - Microsoft's ZeRO optimization
- ✅ **PyTorch FSDP** - Fully Sharded Data Parallel
- ✅ **Accelerate** - HuggingFace's distributed training API
- ✅ **PyTorch Lightning** - High-level training framework
- ✅ **Ray Train** - Multi-node orchestration

### ✅ Phase 8: Optimization (COMPLETE - 6 skills)
**Status**: Core optimization techniques covered

**Completed Skills**:
- ✅ **Flash Attention** - 2-4x faster attention with memory efficiency
- ✅ **bitsandbytes** - 8-bit/4-bit quantization
- ✅ **GPTQ** - 4-bit post-training quantization
- ✅ **AWQ** - Activation-aware weight quantization
- ✅ **HQQ** - Half-Quadratic Quantization without calibration data
- ✅ **GGUF** - llama.cpp quantization format for CPU/Metal inference

### ✅ Phase 9: Evaluation (COMPLETE - 1 skill)
**Status**: Standard benchmarking framework available

**Completed Skills**:
- ✅ **lm-evaluation-harness** - EleutherAI's standard for benchmarking LLMs

### ✅ Phase 10: Inference & Serving (COMPLETE - 4 skills)
**Status**: Production inference frameworks covered

**Completed Skills**:
- ✅ **vLLM** - High-throughput LLM serving with PagedAttention
- ✅ **TensorRT-LLM** - NVIDIA's fastest inference
- ✅ **llama.cpp** - CPU/Apple Silicon inference
- ✅ **SGLang** - Structured generation with RadixAttention

### ✅ Phase 10.5: Infrastructure (COMPLETE - 3 skills)
**Status**: Cloud infrastructure and orchestration covered

**Completed Skills**:
- ✅ **Modal** - Serverless GPU cloud with Python-native API, T4-H200 on-demand
- ✅ **SkyPilot** - Multi-cloud orchestration across 20+ providers with spot recovery
- ✅ **Lambda Labs** - Reserved/on-demand GPU cloud with H100/A100, persistent filesystems

### ✅ Phase 11: Agents (COMPLETE - 4 skills)
**Status**: Major agent frameworks covered

**Completed Skills**:
- ✅ **LangChain** - Most popular agent framework, 500+ integrations
- ✅ **LlamaIndex** - Data framework for LLM apps, 300+ connectors
- ✅ **CrewAI** - Multi-agent orchestration with role-based collaboration
- ✅ **AutoGPT** - Autonomous AI agent platform with visual workflow builder

### ✅ Phase 12: RAG (COMPLETE - 5 skills)
**Status**: Core RAG and vector database skills covered

**Completed Skills**:
- ✅ **Chroma** - Open-source embedding database
- ✅ **FAISS** - Facebook's similarity search, billion-scale
- ✅ **Sentence Transformers** - 5000+ embedding models
- ✅ **Pinecone** - Managed vector database
- ✅ **Qdrant** - High-performance Rust vector search with hybrid filtering

### ✅ Phase 13: Multimodal (COMPLETE - 7 skills)
**Status**: Comprehensive multimodal frameworks covered

**Completed Skills**:
- ✅ **CLIP** - OpenAI's vision-language model
- ✅ **Whisper** - Robust speech recognition, 99 languages
- ✅ **LLaVA** - Vision-language assistant, GPT-4V level
- ✅ **Stable Diffusion** - Text-to-image generation via HuggingFace Diffusers
- ✅ **Segment Anything (SAM)** - Meta's zero-shot image segmentation with points/boxes/masks
- ✅ **BLIP-2** - Vision-language pretraining with Q-Former, image captioning, VQA
- ✅ **AudioCraft** - Meta's MusicGen/AudioGen for text-to-music and text-to-sound

### ✅ Phase 14: Advanced Optimization (COMPLETE)
**Status**: Advanced optimization techniques covered (merged into Phase 8)

**Note**: HQQ and GGUF skills have been completed and merged into Phase 8: Optimization.

### ✅ Phase 15: MLOps & Observability (COMPLETE - 5 skills)
**Status**: Core MLOps and LLM observability covered

**Completed Skills**:
- ✅ **MLflow** - Open-source MLOps platform for tracking experiments
- ✅ **TensorBoard** - Visualization and experiment tracking
- ✅ **Weights & Biases** - Experiment tracking and collaboration
- ✅ **LangSmith** - LLM observability, tracing, evaluation
- ✅ **Phoenix** - Open-source AI observability with OpenTelemetry tracing

### ✅ Phase 16: Prompt Engineering & Advanced Applications (COMPLETE - 6 skills)
**Status**: Core prompt engineering and multi-agent tools covered

**Completed Skills**:
- ✅ **DSPy** - Declarative prompt optimization and LM programming
- ✅ **Guidance** - Constrained generation and structured prompting
- ✅ **Instructor** - Structured output with Pydantic models
- ✅ **Outlines** - Structured text generation with regex and grammars
- ✅ **CrewAI** - Multi-agent orchestration (completed in Phase 11)
- ✅ **AutoGPT** - Autonomous agents (completed in Phase 11)

### ✅ Phase 17: Extended Multimodal (COMPLETE)
**Status**: All extended multimodal skills complete, merged into Phase 13

**Note**: BLIP-2, SAM, and AudioCraft have been completed and merged into Phase 13: Multimodal.

### ✅ Phase 18: Emerging Techniques (COMPLETE - 6 skills)
**Status**: Core emerging techniques covered

**Completed Skills**:
- ✅ **MoE Training** - Mixture of Experts with DeepSpeed/HuggingFace
- ✅ **Model Merging** - mergekit, SLERP, and model composition
- ✅ **Long Context** - RoPE extensions, ALiBi, and context scaling
- ✅ **Speculative Decoding** - Medusa, Lookahead, and draft models for faster inference
- ✅ **Knowledge Distillation** - MiniLLM, reverse KLD, teacher-student training
- ✅ **Model Pruning** - Wanda, SparseGPT, and structured pruning

### ✅ Phase 19: Lab-Equipment Digital Twin Pipeline (COMPLETE — May 2026, v2.0.0 — 36 skills)
**Status**: End-to-end SEM virtualization pipeline covering video capture through VR rendering and physics simulation. All 36 skills are Deep_thinker-verified.

**Completed Categories**:

#### Cat 23 — 3D Reconstruction (7 skills)
- ✅ **Preprocessing Reconstruction Videos** — Raw lab-equipment video → curated keyframes, foreground masks, camera-ready image sets (FFmpeg, BiRefNet, SAM2, pycolmap)
- ✅ **Estimating SfM Camera Poses** — Curated keyframes → sparse COLMAP model (COLMAP 4.0.4+GLOMAP, hloc+SuperPoint+LightGlue, AprilTag/ChArUco metric Sim3 alignment)
- ✅ **Recovering Pose-Free Geometry** — Pose-free dense geometry when COLMAP fails on specular metals (MapAnything, VGGT, DUSt3R, MASt3R)
- ✅ **Training Gaussian Splats** — Primary 3DGS training for lab-equipment digital twins (nerfstudio splatfacto / gsplat 1.5.3, Linux A100)
- ✅ **Extracting GS Surfaces** — Physics-grade collision meshes from 3DGS (2DGS, GOF, PGSR, SuGaR — research-only licenses)
- ✅ **Training Reflection-Aware Splats** — Specular-aware 3DGS for polished steel, anodized aluminum, SEM exteriors (Spec-Gaussian, Ref-GS)
- ✅ **Training NeRF Fallbacks** — NeRF-based fallback when 3DGS fails on transparent specimens or sub-millimeter detail (Nerfacto, Instant-NGP)

#### Cat 24 — 3D Segmentation & Articulation (6 skills)
- ✅ **Per-Gaussian SAGA** — Per-Gaussian contrastive affinity field and boolean masks via SAM (SAGA v2, R&D only)
- ✅ **Articulation Ditto Prior** — Before/after point-cloud articulation hypothesis via Ditto CVPR 2022 (sidecar validator only)
- ✅ **ScrewSplat Articulation** — GS-native joint axis recovery from multi-state RGB (research reference, MIT)
- ✅ **gsplat Scene Adapter** — Canonical PLY I/O, depth-render, and visibility-filter adapter (gsplat v1.5.3, Apache-2.0)
- ✅ **Lift 2D Masks (LUDVIG)** — Per-view mask uplifting into per-Gaussian features (Naver LUDVIG, non-commercial)
- ✅ **Multi-State Diff Open3D** — World-space occupancy differencing to classify revolute/prismatic/screw joints (Open3D, MIT)

#### Cat 25 — Affordance VLM (5 skills)
- ✅ **Multi-View Joint Cards Renderer** — Canonical front/back/left/right/top/bottom grid images from gsplat for VLM passes
- ✅ **Qwen3-VL Affordance Prompter** — Qwen3.6-27B/35B-A3B local A100 inference for joint-type, axis, anchor, range prediction
- ✅ **Kinematic JSON Constrained Decode** — Strict kinematic JSON via OpenAI Structured Outputs, vLLM XGrammar, Outlines, and Pydantic repair loop
- ✅ **Articulation Priors Retrieval** — PartNet-Mobility, GAPartNet, AKB-48 prior retrieval to regularize VLM predictions
- ✅ **VLM Physics Validation Loop** — Actor-critic re-prompt loop with collision/contact checks until JointSpec passes or budget is spent

#### Cat 26 — 3D Rendering & VR (6 skills)
- ✅ **Compiling Splat Assets** — .ply → SOG/streamed LOD (browser), .spz ≤150k (Quest 3 native), GLB KHR_gaussian_splatting (Unity/Unreal)
- ✅ **Publishing SuperSplat WebXR** — HTTPS WebXR publishing for Quest 3 Browser, Pico 4, Apple Vision Pro Safari (no install)
- ✅ **Deploying Quest Spatial Splats** — Native Quest 3/3S APK via Meta Spatial SDK v0.12.0 first-party splat integration
- ✅ **Rendering Unity Splats** — Unity 6 PCVR rendering with aras-p/UnityGaussianSplatting v1.1.1 and OpenXR Multi-Pass
- ✅ **Rendering Unreal XScene Splats** — UE5.5–5.7 PCVR rendering via DazaiStudio/SplatRenderer-UEPlugin and XVerse XScene
- ✅ **Editing SuperSplat Scenes** — PlayCanvas SuperSplat Editor v2.25.0 for floater removal, camera bookmarks, and scene annotation

#### Cat 27 — Physics Simulation (7 skills)
- ✅ **Prototyping Genesis Physics** — Fast GPU physics experiments with genesis-world (MPM, granular, fluid, deformable, differentiable)
- ✅ **Authoring URDF/MJCF/USD** — Single neutral component dictionary → synchronized URDF, MJCF, and USD for multi-simulator interchange
- ✅ **Conditioning Collision Meshes** — 3DGS-derived visual mesh → watertight, simplified, CoACD-decomposed collision geometry
- ✅ **Simulating MuJoCo/MJX** — Default lab-equipment simulator: CPU MuJoCo authoring + JAX MJX batched GPU rollouts
- ✅ **Validating Isaac Sim/Lab** — Secondary validation in NVIDIA Isaac Sim 5.1 + Isaac Lab 2.3.x with USD/Omniverse workflows
- ✅ **Validating SAPIEN Articulations** — Cross-simulator joint axis and collision group sanity-check via SAPIEN 3.x (PhysX 5 GPU)
- ✅ **Calibrating SysID RL Hooks** — Optuna+scipy sim-to-real parameter calibration with Gymnasium-compatible wrappers

#### Cat 28 — Digital Twin Workflows — META (5 skills)
- ✅ **Multi-State Capture Protocol** — K-state camera placement and lighting protocol generator for SEM, optical microscopes, optical benches
- ✅ **Versioning Twins with ARA** — OpenUSD 26.x scene + ARA cognitive layer + SPDX/CycloneDX BOM for versioned, citeable twins
- ✅ **Lab Equipment Twinning** — End-to-end orchestrator routing an agent through capture → pose → 3DGS → segmentation → affordance → physics → VR
- ✅ **Validating Digital Twins** — META QA gate-keeper emitting qa_report.json with pass/fail for all pipeline stages
- ✅ **Simulating Experiment Runs in Twins** — META skill for SEM parameter sweeps, protocol replay, and batch RL training via Hydra+Optuna+W&B

## Contributing to the Roadmap

Want to help us achieve these goals?

1. **Pick a skill from the roadmap** - Comment on [GitHub Discussions](https://github.com/orchestra-research/AI-research-SKILLs/discussions) to claim it
2. **Follow the [contribution guide](CONTRIBUTING.md)** - Use our template and quality standards
3. **Submit your PR** - We review within 48 hours

## 🎉 Roadmap Complete!

All 70 skills have been completed! The library now covers the full AI research lifecycle:

1. ✅ **Phase 1-10**: Core ML infrastructure (Architecture, Tokenization, Fine-Tuning, Data Processing, Post-Training, Safety, Distributed Training, Optimization, Evaluation, Inference)
2. ✅ **Phase 10.5**: Infrastructure (Modal, SkyPilot, Lambda Labs)
3. ✅ **Phase 11-12**: Applications (Agents, RAG)
4. ✅ **Phase 13**: Multimodal (CLIP, Whisper, LLaVA, Stable Diffusion, SAM, BLIP-2, AudioCraft)
5. ✅ **Phase 14-16**: Advanced (Optimization, MLOps & Observability, Prompt Engineering)
6. ✅ **Phase 17-18**: Extended (Extended Multimodal, Emerging Techniques)

## 🎉 May 2026 — v2.0.0 Milestone: Lab-Equipment Digital Twin Pipeline

36 new skills (categories 23–28) bring the total to **134 skills across 29 categories**:

7. ✅ **Phase 19**: Lab-Equipment Digital Twin — 3D Reconstruction (cat 23), 3D Segmentation & Articulation (cat 24), Affordance VLM (cat 25), 3D Rendering & VR (cat 26), Physics Simulation (cat 27), Digital Twin Workflows / META (cat 28)

This phase targets the SEM (scanning electron microscope) virtualization use case: handheld video → camera poses → 3D Gaussian Splatting → moving-part cluster detection → VLM affordance/kinematic hypothesis → URDF/physics authoring → VR rendering on Quest 3 / WebXR / Unity / Unreal. All 36 skills are Deep_thinker-verified.

## Future Directions

While the roadmap milestones are complete, the library will continue to evolve with:
- **Updates**: Keeping existing skills current with latest versions
- **Community contributions**: Additional skills from contributors
- **Emerging tools**: New frameworks and techniques as they mature

## Philosophy

**Quality over Quantity**: Each skill must provide real value with comprehensive guidance, not just links to docs. We aim for 300+ lines of expert-level content per skill, with real code examples, troubleshooting guides, and production-ready workflows.
