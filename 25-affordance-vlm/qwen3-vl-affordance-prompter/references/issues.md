# Qwen3-VL / VLM Stack Issues and Tested Versions

Maintain this file alongside SKILL.md as a tested issue/version log. Update entries with reproduction steps, environment details, and links.

## Qwen3-VL

- #1477 invalid vLLM install instruction: https://github.com/QwenLM/Qwen3-VL/issues/1477
- #1540 do_resize=False in vLLM/video reproduction: https://github.com/QwenLM/Qwen3-VL/issues/1540
- #1545 Python 3.13 / CUDA / vLLM 0.11.0 demo failure with 262144 max sequence length and large encoder cache: https://github.com/QwenLM/Qwen3-VL/issues/1545
- #1557 vLLM vs Transformers result inconsistency with Qwen3-VL preprocessing: https://github.com/QwenLM/Qwen3-VL/issues/1557
- #1780 click coordinates reported off for Qwen3-VL-32B-Thinking: https://github.com/QwenLM/Qwen3-VL/issues/1780
- #32 repeated HF inference memory growth / OOM: https://github.com/QwenLM/Qwen3-VL/issues/32

Tested working stack on A100 80GB:

- Driver >= 570.26
- CUDA wheel profile cu128
- Python 3.12 (NOT 3.13)
- torch==2.8.0, torchvision==0.23.0
- transformers>=4.57.0,<4.58
- qwen-vl-utils==0.0.14
- vllm==0.11.0
- flash-attn>=2.8,<2.9 (optional; falls back to SDPA)

vLLM serve flags that prevent OOM on A100 80GB:

```
--max-model-len 32768
--max-num-seqs 1                # 32B
--max-num-seqs 8                # 8B only after testing
--limit-mm-per-prompt '{"image":8,"video":0}'
--gpu-memory-utilization 0.90
--mm-processor-cache-gb 1
```

Pixel budget defaults:

- 8B: `max_pixels = 768 * 32 * 32`
- 32B: `max_pixels = 512 * 32 * 32`

## vLLM / Qwen2.5-VL

- vLLM #13579 KeyError 'qwen2_5_vl' loading Qwen2.5-VL 72B 4-bit: https://github.com/vllm-project/vllm/issues/13579
- LLaMA-Factory #6784 KeyError 'qwen2_5_vl' with older Transformers: https://github.com/hiyouga/LLaMA-Factory/issues/6784

Resolution: ensure `transformers>=4.57.0`. Fresh `uv venv --python 3.12 --seed`.

## InternVL

- InternVL #1103 visual grounding quality discussion: https://github.com/OpenGVLab/InternVL/issues/1103
- InternVL3.5-38B vLLM compatibility / processor-cache repeated HTTP HEAD / 429: https://huggingface.co/OpenGVLab/InternVL3_5-38B/discussions/2

InternVL3.5 model card: up to 30B fits one A100; 38B requires 2x A100 in BF16. On one A100, prefer 14B.

## SpatialRGPT

- SpatialRGPT #21 pydantic / Gradio schema failure: https://github.com/AnjieCheng/SpatialRGPT/issues/21
- Detectron2 CUDA_HOME install note: https://github.com/AnjieCheng/SpatialRGPT

Demo env (separate from main):

```bash
pip install gradio==4.27 deepspeed==0.13.0 gradio_box_promptable_image segment_anything_hq
pip install 'git+https://github.com/facebookresearch/detectron2.git@ff53992b1985b63bd3262b5a36167098e3dada02'
export CUDA_HOME=/usr/local/cuda-12.1
```

## SpatialBot

- #2 device mismatch ("Expected all tensors to be on the same device"): https://github.com/BAAI-DCAI/SpatialBot/issues/2
- #4 cannot access gated repo: https://github.com/BAAI-DCAI/SpatialBot/issues/4
- #5 batched inference question: https://github.com/BAAI-DCAI/SpatialBot/issues/5
- #6 SigLIP / depth processing question: https://github.com/BAAI-DCAI/SpatialBot/issues/6

Workaround for device mismatch:

```python
model.get_vision_tower().to("cuda")
# or
model.model.vision_tower = model.model.vision_tower.to("cuda")
```

Gated repo: `huggingface-cli login` then accept terms.

## License and release matrix

| Component                  | Repo license   | Model-card / weight license                                       | Last named release relevant to this skill           |
|----------------------------|----------------|-------------------------------------------------------------------|-----------------------------------------------------|
| Qwen3-VL                   | Apache-2.0     | Qwen3-VL-8B/32B Instruct/Thinking: Apache-2.0                     | 8B 2025-10-15; 32B 2025-10-21; paper 2025-11-27     |
| InternVL                   | MIT (repo)     | InternVL3.5 cards: Apache-2.0 (verify per checkpoint)             | 2025-08-26; CascadeRL code 2025-08-30               |
| SpatialRGPT                | Apache-2.0     | HF checkpoint card lacks full license; verify before redist        | Code/dataset/benchmark 2024-10-07                   |
| SpatialBot                 | MIT (repo)     | SpatialBot-3B: CC-BY-4.0; data CC-BY-4.0                          | No GitHub releases; updated around 2024             |
| Qwen2.5-VL-72B-AWQ         | Qwen family    | Qwen license for 72B/AWQ                                           | AWQ 72B with Qwen2.5-VL technical report 2025-02-20 |
| Molmo / MolmoPoint         | Molmo2 Apache-2.0 | MolmoPoint-8B: Apache-2.0 with responsible-use note             | MolmoPoint announced 2026-03-18                     |
