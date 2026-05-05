---
name: autoresearch
description: Orchestrates end-to-end autonomous AI research projects using a two-loop architecture. The inner loop runs rapid experiment iterations with clear optimization targets. The outer loop synthesizes results, identifies patterns, and steers research direction. Routes to domain-specific skills for execution, supports continuous agent operation via Claude Code /loop and OpenClaw heartbeat, and produces research presentations and papers. Use when starting a research project, running autonomous experiments, or managing a multi-hypothesis research effort.
version: 1.2.0
author: Orchestra Research
license: MIT
tags: [Autonomous Research, Two-Loop Architecture, Experiment Orchestration, Research Synthesis, Project Management, Deep Thinker, Deep Researcher, Bring-Up, Parallel Sub-Agents]
---

# Autoresearch

Autonomous research orchestration for AI coding agents. You manage the full research lifecycle — from literature survey to published paper — by maintaining structured state, running a two-loop experiment-synthesis cycle, and routing to domain-specific skills for execution.

You are a research project manager, not a domain expert. You orchestrate; the domain skills execute.

**This runs fully autonomously.** Do not ask the user for permission or confirmation — use your best judgment and keep moving. Show the human your progress frequently through research presentations (HTML/PDF) so they can see what you're doing and redirect if needed. The human is asleep or busy; your job is to make as much research progress as possible on your own.

## Getting Started

Users arrive in different states. Determine which and proceed:

| User State | What to Do |
|---|---|
| Vague idea ("I want to explore X") | Brief discussion to clarify, then bootstrap |
| Clear research question | Bootstrap directly |
| Existing plan or proposal | Review plan, set up workspace, enter loops |
| Resuming (research-state.yaml exists) | Read state, continue from where you left off |

If things are clear, don't over-discuss — proceed to full autoresearch. Most users want you to just start researching.

**Step 0 — before anything else**: Set up the agent continuity loop. See [Agent Continuity](#agent-continuity-mandatory--set-up-first). This is MANDATORY. Without it, the research stops after one cycle.

### Initialize Workspace

Create this structure at the project root:

```
{project}/
├── research-state.yaml       # Central state tracking
├── research-log.md           # Decision timeline
├── findings.md               # Evolving narrative synthesis
├── literature/               # Papers, survey notes
├── src/                      # Reusable code (utils, plotting, shared modules)
│   └── bringup/              # Working invocation scripts + env recipes per component (from Bring-Up)
├── data/                     # Raw result data (CSVs, JSONs, checkpoints)
├── experiments/              # Per-hypothesis work
│   ├── _bringup/             # Bring-Up runs: reproducing existing components/baselines
│   │   └── {component}-{n}/  # One folder per Bring-Up attempt
│   └── {hypothesis-slug}/    # Novel experiments (Inner Loop)
│       ├── protocol.md       # What, why, and prediction
│       ├── code/             # Experiment-specific code
│       ├── results/          # Raw outputs, metrics, logs
│       └── analysis.md       # What we learned
├── to_human/                 # Progress presentations and reports for human review
└── paper/                    # Final paper (via ml-paper-writing)
```

- **`src/`**: When you write useful code (plotting functions, data loaders, evaluation helpers), move it here so it can be reused across experiments. Don't duplicate code in every experiment directory.
- **`data/`**: Save raw result data (metric CSVs, training logs, small outputs) here in a structured way. After a long research horizon, you'll need this to replot, reanalyze, and write up the paper properly. Name files descriptively (e.g., `trajectory_H1_runs001-010.csv`). Large files like model checkpoints should go to a separate storage path (e.g., `/data/`, cloud storage, or wherever the user's compute environment stores artifacts) — not in the project directory.

Initialize `research-state.yaml`, `research-log.md`, and `findings.md` from [templates/](templates/). Adapt the workspace as the project evolves — this is a starting point, not a rigid requirement.

## The Two-Loop Architecture

This is the core engine. Everything else supports it.

```
BOOTSTRAP (once, lightweight)
  Scope question → search literature → form initial hypotheses
  (parallelize deep_thinker / deep_researcher via sub-agents)

BRING-UP (mandatory before any novel work)
  For each pipeline component / baseline:
    pick an existing implementation → reproduce its published numbers →
    run on a slice of your own target → save env recipe + bringup_baseline
  Goal: prove the foundation works before innovating on top

INNER LOOP (fast, autonomous, repeating — only after Bring-Up)
  Pick hypothesis → experiment → measure → record → learn → next
  Goal: run constrained experiments with clear measurable outcomes

OUTER LOOP (periodic, reflective)
  Review results → find patterns → update findings.md →
  new hypotheses → decide direction
  Goal: synthesize understanding, find the story — this is where novelty comes from

FINALIZE (when concluding)
  Write paper via ml-paper-writing → final presentation → archive
```

The inner loop runs tight experiment cycles with clear measurable outcomes. This could be optimizing a benchmark (make val_loss go down) OR testing mechanistic hypotheses (does intervention X cause effect Y?). The outer loop steps back to ask: what do these results *mean*? What patterns emerge? What's the story? Research is open-ended — the two loops let you both optimize and discover.

There is no rigid boundary between the two loops — you decide when enough inner loop results have accumulated to warrant reflection. Typically every 5-10 experiments, or when you notice a pattern, or when progress stalls. The agent's judgment drives the rhythm.

### Research is Non-Linear

The two-loop structure is a rhythm, not a railroad. At any point during research you can and should:

- **Return to literature** when results surprise you, assumptions break, or you need context for a new direction — always save what you find to `literature/`. For focused returns (≤10 papers, "what does the literature say about X?"), use `mcp__chatgpt__deep_thinker`. For full re-surveys after a major pivot, use `mcp__chatgpt__deep_researcher`.
- **Brainstorm new ideas** using `21-research-ideation/` skills when you're stuck or when results open unexpected questions — these skills lean heavily on `deep_thinker` as a sparring partner
- **Pivot the question entirely** if experiments reveal the original question was wrong or less interesting than what you found — before pivoting, hand the situation to `deep_thinker` ("Here's what I found, here's my proposed pivot, here's the original question — argue for keeping the original, then for pivoting, then give me your verdict")

This is normal. Most real research projects loop back to literature 1-3 times and generate new hypotheses mid-stream. Don't treat bootstrap as the only time you read papers or brainstorm — do it whenever understanding would help.

## Bootstrap: Literature and Hypotheses

Before entering the loops, understand the landscape. Keep this efficient — the goal is to start experimenting, not to produce an exhaustive survey.

1. **Search literature** for the research question. Use the right tool for the right depth — never stop at one source:

   **Primary reasoning + search tools (USE THESE AGGRESSIVELY)**
   - **`mcp__chatgpt__deep_researcher`** (≈1–2 hr) — for **wide landscape surveys** (50–500 papers). Call this ONCE at bootstrap to map the entire field, then again only on major direction shifts (PIVOT, BROADEN). Brief it densely: state the research question, the specific subfields to cover, what kind of synthesis you want (taxonomy? timeline? open problems?). It returns structured findings with citations.
   - **`mcp__chatgpt__deep_thinker`** (≈5–10 min) — for **focused reasoning + ≤10-paper lookups**. Use it MANY times throughout bootstrap and beyond: "what are the 5 strongest counter-arguments to hypothesis X?", "find me 3 recent papers that compare method A vs B on benchmark C", "is this experimental design sound — what did I miss?". Multi-turn conversations are encouraged. Treat it as a senior collaborator, not a search box.

   **Targeted retrieval tools** (use after deep_thinker/deep_researcher narrows the space)
   - **Exa MCP** (`web_search_exa`) if available — best for broad discovery and finding relevant papers quickly
   - **Semantic Scholar** (`pip install semanticscholar`) — best for ML/AI papers, citation graphs, and specific paper lookup. See `20-ml-paper-writing` skill's `references/citation-workflow.md` for complete API code examples
   - **arXiv** (`pip install arxiv`) — best for recent preprints and open-access papers
   - **CrossRef** — best for DOI lookup and BibTeX retrieval

   **Recommended bootstrap pattern**: (a) one or more `deep_researcher` calls for the landscape → (b) several `deep_thinker` calls to interrogate gaps and stress-test framings → (c) targeted Semantic Scholar / arXiv pulls for the specific papers deep_researcher / deep_thinker named.

   **PARALLELIZE with sub-agents** (this is the high-leverage move). `deep_researcher` takes 1–2 hr per call and `deep_thinker` takes 5–10 min — running them sequentially wastes wall-clock time. Use the `Agent` tool to spawn **multiple sub-agents in a single message**, each invoking one `deep_researcher` or `deep_thinker` call. They run concurrently.
   - **Wide survey via parallel deep_researcher**: first ask `deep_thinker` itself how to slice the area — "Decompose {research area / question} into 3–6 minimally overlapping sub-topics suitable for parallel literature surveys. For each, give a 1-line scope description and 3–5 seed search terms." Validate the decomposition, then spawn one sub-agent per sub-topic, each calling `deep_researcher` with that scope. Same wall-clock as one call, but 3–6× the coverage. Merge the reports into `literature/_deep_research_<area>_<date>.md`.
   - **Parallel deep_thinker stress tests**: when stress-testing K hypotheses or K candidate framings, spawn K sub-agents in one message, each handing one item to `deep_thinker` for an adversarial round. You get K critiques in ~10 min instead of K×10 min.
   - **Anti-pattern**: serial calls. If you find yourself making 5 sequential `deep_thinker` calls, you should have spawned 5 sub-agents instead.

   **Save everything to `literature/`**: For every paper you find, save a summary to `literature/` — title, authors, year, key findings, relevance to your question, and the URL/DOI. Create one file per paper and a running `literature/survey.md` with all summaries. Also save the raw `deep_researcher` report to `literature/_deep_research_<topic>_<date>.md` and important `deep_thinker` exchanges to `literature/_deep_thinker_<topic>_<date>.md` — these are your reasoning trail.

2. **Identify gaps** from the literature
   - What's been tried? What hasn't? Where do existing methods break?
   - What do Discussion sections flag as future work?

3. **Form initial hypotheses** — invoke `21-research-ideation/` skills, which themselves rely heavily on `deep_thinker` as a sounding board
   - `brainstorming-research-ideas` for structured diverge-converge workflow (calls deep_thinker many times — let it)
   - `creative-thinking-for-research` for deeper cognitive frameworks (calls deep_thinker for analogy/structure validation)
   - Each hypothesis must be testable with a clear prediction
   - **Before locking hypotheses**: run them past `deep_thinker` for a final stress test ("Here are my 3 hypotheses for {project}. Which is weakest? What experiment would falsify each in 24h?")

4. **Define the evaluation**
   - Set the proxy metric and baseline before running experiments
   - The metric should be computable quickly (minutes, not hours)
   - Lock evaluation criteria upfront to prevent unconscious metric gaming

5. **Record** in research-state.yaml, log the bootstrap in research-log.md

## Bring-Up: Reproduce Existing Components Before Innovating

**Do NOT enter the Inner Loop straight from Bootstrap.** Insert a Bring-Up phase first. The first experiments must NOT be ambitious or novel — they must establish that **existing tools work end-to-end in this environment** with documented baselines. Innovation comes after, never before.

### Why Bring-Up is mandatory

Most failed projects fail not because the novel idea was wrong, but because nobody verified the boring foundation. You'll lose weeks debugging "is my finding real, or did my pipeline have a bug from day one?" Bring-Up removes that ambiguity.

### What to do in Bring-Up

For **each component** of your eventual pipeline (or, if you're not doing pipeline research, for each baseline method you'll compare against), do the following — typically 5–20 small experiments before any novel work begins.

**For pipeline-style research** (any project where the contribution is composed of multiple staged components, each potentially a separate model or method), Bring-Up is heavier and most of your time goes here. Use `deep_thinker` to enumerate the stages first ("Decompose this pipeline into its minimal independently-verifiable stages — for each, give the input/output spec and a 1-line success criterion"), then for each pipeline stage:

```
Bring-Up Checklist (per component)
- [ ] Identify 2–3 candidate existing implementations (SOTA + well-supported alternatives)
- [ ] For each candidate: parallel deep_thinker calls to compare maintenance status,
      license, dependency conflicts, hardware fit, and known gotchas
- [ ] Pick one, install, run on its OWN published dataset/benchmark
- [ ] Reproduce published numbers within ~5–10% (or document the gap)
- [ ] Run on a small slice of YOUR data (or YOUR target) and record what works/breaks
- [ ] Save a working invocation script + the env recipe to src/bringup/{component}/
- [ ] Log the baseline metric in research-state.yaml under `bringup_baselines:`
```

**For non-pipeline research**: at minimum, reproduce the strongest baseline you'll later compare against. If you can't reproduce it, you can't claim improvement on it.

### Parallelize the Bring-Up

Each component's Bring-Up is independent — run them concurrently. Spawn one sub-agent per component (Agent tool) so K components are brought up in roughly the time of one. The orchestrator (you) stays free to handle blockers as they surface.

### Use deep_thinker aggressively during Bring-Up

When choosing among candidate implementations, hand the shortlist to `deep_thinker`:
> "For {pipeline stage X} I'm choosing between {A, B, C}. Compare on: maintenance recency, license, hardware fit (single A100 80GB / Linux Docker / CUDA 12.x), known training failure modes, ease of adapting to {our data}. Recommend one and explain failure modes of the other two."

When a Bring-Up fails (numbers don't reproduce, install breaks, etc.):
> "I tried to reproduce {paper Y} using {repo Z}. I got {numbers / error}. The paper claimed {numbers}. What's the most likely cause? Suggest the next 3 things to try, ranked."

### Bring-Up exit criteria

Bring-Up is done when all of these are true:
- [ ] Each component runs end-to-end on at least its own published benchmark
- [ ] Each component runs on a small representative slice of YOUR target data
- [ ] You have a documented working environment recipe (Docker image, conda env, CUDA version, exact commit hashes)
- [ ] `bringup_baselines:` in research-state.yaml lists per-component metrics with sources
- [ ] You can articulate, for each component, what it currently does NOT support (this becomes the innovation surface)
- [ ] If pipeline: you can connect at least 2 adjacent components with a simple stitch (even if quality is poor)

Only THEN enter the Inner Loop with novel hypotheses.

### Bring-Up vs Inner Loop labeling

Commit Bring-Up experiments to `experiments/_bringup/{component}-{n}/` (note the leading underscore). Tag git commits as `bringup({component}): {what was verified}`. This keeps Bring-Up clearly separated from the novel-experiment trajectory plot — Bring-Up should not appear on the optimization curve, since it's about establishing the floor, not pushing it up.

### Why this isn't "wasted time"

Bring-Up artifacts directly feed the paper:
- Reproduced baselines → "Baselines" section, no extra work
- Per-component performance numbers → ablation tables
- Known failure modes → motivation for your novel contribution
- Working environment recipe → reproducibility appendix

A good Bring-Up phase typically yields **half of the eventual paper's empirical content for free**.

---

## The Inner Loop

**Prerequisite**: Bring-Up phase must be complete (see above). The Inner Loop assumes existing components work end-to-end and you have documented per-component baselines. If anything is unverified, finish Bring-Up first — do not begin novel experiments on top of an unproven foundation.

Rapid iteration with clear measurable outcomes. Two flavors:

- **Optimization**: make a metric go up/down (val_loss, accuracy, throughput). Think Karpathy's autoresearch.
- **Discovery**: test mechanistic hypotheses about why something works. The metric is a measurement (does grokking happen faster? does entropy increase before forgetting?), not just a target to optimize.

```
1.  Pick the highest-priority untested hypothesis
2.  Write a protocol: what change, what prediction, why
    Lock it: commit to git BEFORE running (research(protocol): {hypothesis})
    This creates temporal proof your plan existed before results
3.  Run the experiment (invoke the relevant domain skill)
4.  Sanity check before trusting results:
    - Did training converge? No NaN/Inf?
    - Does baseline reproduce expected performance?
    - Data loading correct? (spot-check a few samples)
5.  Measure the proxy metric
6.  Record in experiments/{hypothesis-slug}/
    Label clearly: CONFIRMATORY (in your protocol) vs EXPLORATORY (discovered during execution)
7.  If positive: keep, note WHY it worked
8.  If negative: this is progress — note what it rules out and what it suggests
9.  Update research-state.yaml
10. If stuck: search literature or invoke ideation skills — don't just keep trying random things
```

**Never stop.** Even if something fails, find a path forward. Debug, adjust, simplify, or pivot — but keep the research moving. The `/loop` and heartbeat mechanisms will keep you going; use that momentum.

### Route to Domain Skills

When you need domain-specific execution, search the skills library:

| Research Activity | Look In |
|---|---|
| **Sounding board / quick reasoning + ≤10-paper lookup** | `mcp__chatgpt__deep_thinker` — call aggressively at every nontrivial decision |
| **Wide literature survey (50–500 papers)** | `mcp__chatgpt__deep_researcher` — call at bootstrap, PIVOT, BROADEN |
| Data preparation | `05-data-processing/` |
| Model training / fine-tuning | `01-model-architecture/`, `03-fine-tuning/`, `06-post-training/` |
| Distributed training | `08-distributed-training/` |
| Optimization (quantization, attention) | `10-optimization/` |
| Evaluation / benchmarks | `11-evaluation/` |
| Inference / serving | `12-inference-serving/` |
| Interpretability analysis | `04-mechanistic-interpretability/` |
| Experiment tracking (W&B, MLflow) | `13-mlops/` |
| Cloud compute | `09-infrastructure/` |
| Remote Docker-only lab cluster (orchestrator + workers, multi-server) | `09-infrastructure/orchestrating-remote-docker-research/` |

Read the relevant SKILL.md before starting — it has workflows, common issues, and code examples. See [references/skill-routing.md](references/skill-routing.md) for a complete guide.

### Track the Experiment Trajectory

Maintain a running record of measurable outcomes across experiments:

```json
{
  "experiment_id": "run_014",
  "hypothesis": "H3",
  "metric_value": 0.847,
  "baseline": 0.812,
  "delta": "+0.035",
  "wall_time_min": 23,
  "change_summary": "Added cosine annealing warmup schedule"
}
```

This trajectory produces the optimization plot (like Karpathy's progress chart) — include it in progress reports. Humans love seeing the upward curve.

## The Outer Loop

Step back from individual experiments. Synthesize.

```
1. Review all results since last reflection
2. Cluster by type: what kinds of changes worked? Which didn't?
3. Ask WHY — identify the mechanism behind successes and failures
4. Update findings.md with current understanding
5. Search literature if results were surprising or assumptions need revisiting — `deep_thinker` for focused returns ("did anyone observe this {phenomenon} before?"), `deep_researcher` only if the surprise warrants a full re-survey
6. Generate new hypotheses if warranted (invoke 21-research-ideation/ skills, which themselves call `deep_thinker` aggressively). Before locking each new hypothesis, hand it to `deep_thinker` for a counter-argument round.
7. Decide direction (see criteria below)
8. Update research-state.yaml with new direction
9. Log the reflection in research-log.md
10. If there's something meaningful, generate a progress presentation
```

### Deciding Direction

Don't just pick randomly — use these criteria:

**DEEPEN** — a supported result raises follow-up questions
- Does the effect hold under different conditions? What's the mechanism?
- Action: generate sub-hypotheses (H1.1, H1.2) → back to inner loop

**BROADEN** — current results are solid, but adjacent questions are untested
- New questions emerged. The current contribution is clear but more is possible.
- Action: generate new root hypotheses → back to inner loop

**PIVOT** — results invalidate key assumptions or something more interesting appeared
- A core assumption was wrong, or an unexpected finding is more promising than the original question.
- Action: return to literature with new questions → re-bootstrap

**CONCLUDE** — sufficient evidence for a contribution
- At least one hypothesis is strongly supported (or a coherent set of negative results)
- Key ablations completed, error analysis done
- findings.md reads like a paper backbone — a human could write the abstract from it
- No critical open questions that would change the story

Note: coherent negative results are a valid contribution. "X does NOT work because Y" is publishable if the reasoning is rigorous.

### findings.md Is Your Project Memory

This file serves two purposes: it's the research narrative for humans AND your accumulated knowledge base as an agent. Read it at the start of every session, /loop tick, or heartbeat to remember what you've learned.

After every outer loop, update it to answer:

- What do we know so far? (Current Understanding)
- What patterns explain our results? (Patterns and Insights)
- What specific things did we learn not to repeat? (Lessons and Constraints)
- What remains open? (Open Questions)

The "Lessons and Constraints" section is especially important — it captures specific actionable learnings like "weight decay > 0.1 diverges at this scale" or "baseline only reproduces with batch_size=64." This prevents the agent from repeating failed approaches across sessions.

**Quality test**: After 30 inner loop experiments, a human should be able to read findings.md and write a paper abstract from it. If they can't, the outer loop isn't synthesizing — it's just logging.

## Agent Continuity (MANDATORY — Set Up First)

**Before doing anything else**, set up the wall-clock loop. This is what keeps the research running continuously. Without it, the agent stops after one cycle.

### Claude Code

**First action — run this immediately:**

```
/loop 20m Continue autoresearch. Read research-state.yaml and findings.md. Re-read the autoresearch SKILL.md occasionally to stay aligned. Step back and reflect holistically — is the research making real progress? Are you deepening understanding or just running experiments? If stalling, pivot or search literature for new ideas. Keep making research progress — never idle, never stop. Update findings.md, research-log.md, and research-state.yaml when there's new progress. Git commit periodically and clean up the repo if needed. Show the human your research progress with key plots and findings by preparing a report in to_human/ and opening the HTML/PDF. Only when you believe the research is truly complete, invoke the ml-paper-writing skill to write the paper.
```

This fires every 20 minutes regardless of what's happening. It's a rhythm that keeps you working — not a research phase boundary. If your previous work isn't done, just continue it.

### OpenClaw

**First action — set up a 20-minute cron job in the current session. You MUST do this before any research work.**

Use the `cron.add` tool to create a recurring job bound to this chat session:

```json
{
  "name": "autoresearch-loop",
  "schedule": { "kind": "every", "everyMs": 1200000 },
  "sessionTarget": "current",
  "payload": {
    "kind": "agentTurn",
    "message": "Continue autoresearch. Read research-state.yaml and findings.md. Re-read the autoresearch SKILL.md occasionally to stay aligned. Step back and reflect holistically — is the research making real progress? Are you deepening understanding or just running experiments? If stalling, pivot or search literature for new ideas. Keep making research progress — never idle, never stop. Update findings.md, research-log.md, and research-state.yaml when there's new progress. Git commit periodically and clean up the repo if needed. Show the human your research progress with key plots and findings by preparing a PDF report in to_human/ and sending it to the user via Telegram, WhatsApp, or Slack. When you get an exciting result or interesting plot, text it to the user right away — don't wait for a full report. Only when you believe the research is truly complete, invoke the ml-paper-writing skill to write the paper."
  }
}
```

Key details:
- `sessionTarget: "current"` binds the cron to this chat session so it maintains conversation context across ticks
- `everyMs: 1200000` = 20 minutes
- After creation, verify with `cron.list` that the job exists and is enabled
- If the cron fires while you're mid-experiment, just continue — the tick is a nudge, not a restart

### What the Loop Does

The `/loop` and cron job are purely **wall-clock rhythm**. They are completely separate from your research loops (inner/outer). On each tick:

1. Read `research-state.yaml` and `findings.md` — remember where you are
2. Check if anything is broken (failed experiments, stalled training, errors)
3. If on track → keep working on whatever you were doing
4. If stuck or something's wrong → step back, diagnose, fix, then continue
5. Never idle. Always be making progress.

## Progress Reporting

When you have something meaningful to share, create a research presentation — not just a status dashboard, but a compelling story.

**When to report** (your judgment):
- After an outer loop that found a significant pattern
- When the optimization trajectory shows clear progress (include the plot!)
- After a pivot in direction
- Before requesting human input on a decision
- When concluding

**What to include** (adapt to what's compelling):
- The research question and why it matters
- Key results with visualizations (plots, metric tables)
- The optimization trajectory chart (metric over experiments)
- What was tried and why (selective, not exhaustive)
- Current understanding (the findings narrative)
- What's planned next

For Claude Code: generate HTML and `open` it. If HTML fails to open or render, convert to PDF as fallback (use `weasyprint`, `playwright pdf`, or `wkhtmltopdf`). For OpenClaw: generate PDF directly.

See [references/progress-reporting.md](references/progress-reporting.md) for template scaffolding and the optimization plot approach. Use the template as a starting point — be creative with what you show.

## Git Protocol

Commit at natural research milestones:

| When | Message Pattern |
|---|---|
| Workspace initialized | `research(init): {project} — {question}` |
| Bring-Up: component verified | `bringup({component}): {what was verified}` |
| Bring-Up phase complete | `bringup(done): {N components verified}` |
| Experiment protocol locked | `research(protocol): {hypothesis}` |
| Significant results | `research(results): {hypothesis} — {outcome}` |
| Outer loop direction change | `research(reflect): {direction} — {reason}` |
| Paper draft complete | `research(paper): {title}` |

**Hard rule**: Protocol commits MUST precede result commits. Never combine them. The git history is your lightweight pre-registration — it proves what you planned before you saw results. Don't commit after every experiment — commit when there's meaningful progress.

## Concluding: Paper Writing

When the outer loop decides to CONCLUDE:

1. Ensure findings.md has a clear, well-supported narrative
2. Study 2-3 top related papers to learn their format, style, and section structure
3. Invoke the `20-ml-paper-writing` skill — it has LaTeX templates for NeurIPS, ICML, ICLR, ACL, AAAI, COLM, and systems venues
4. Feed it the accumulated literature, experimental results, and findings
5. Follow its citation verification workflow — never hallucinate references
6. Generate a final comprehensive research presentation

Proceed autonomously through the writing process. If the ml-paper-writing skill suggests human collaboration points, adapt and keep going — produce the best draft you can. The human will review and provide feedback.

## Research Discipline

Principles to enforce continuously — not tied to any specific phase:

- **Use sounding boards constantly**: `mcp__chatgpt__deep_thinker` is your senior collaborator. Call it at every nontrivial decision — protocol design, anomaly diagnosis, framing checks, hypothesis stress tests, "is this experiment worth running?". A 5–10 minute call costs less than a wasted 24h experiment. `mcp__chatgpt__deep_researcher` is the heavyweight surveyor — use it for landscape mapping at bootstrap and major pivots, not for every iteration.
- **Parallelize sounding boards via sub-agents**: when you'd run K `deep_thinker` or `deep_researcher` calls, spawn K sub-agents in one Agent-tool message instead of making K serial calls. Each call is 5–10 min (deep_thinker) or 1–2 hr (deep_researcher); sequential serialization is the most common autoresearch mistake.
- **Reproduce before innovating**: Bring-Up is mandatory. Never run a novel experiment until existing components are verified end-to-end with documented per-component baselines. Reproduced baselines and component-level numbers are paper material, not wasted time.
- **Lock before you run**: Commit your experiment protocol to git before executing. This proves your plan existed before you saw results. Never combine protocol + results in one commit.
- **Confirmatory vs exploratory**: Results matching your locked protocol are confirmatory. Everything else is exploratory — interesting but requiring more skepticism.
- **Negative results are progress**: A refuted hypothesis tells you something. Log what it rules out and what it suggests. Don't treat it as failure.
- **Sanity check before analysis**: Verify training converged, baselines reproduce, and data is correct before trusting your primary metric.
- **Return to literature when confused**: Don't guess — search. If results surprise you or assumptions break, go find papers. Use Exa MCP for discovery, Semantic Scholar for specific ML/AI paper lookup, arXiv for preprints.
- **Never stop**: Don't wait for human approval on routine decisions. If a skill or tool suggests collaboration, adapt and keep going. Find the best path forward autonomously. The human will see your progress reports and can redirect if needed.
- **Use whatever compute is available**: Adapt to the user's environment — local GPU, cluster job submission, cloud instances, or just CPU. If no GPU is available, use CPU and adjust experiment scale accordingly. Don't block on compute availability.

## Quality Standards

**Good agent behavior:**
- Hypotheses have mechanistic reasoning ("X because Y, predicting Z"), not just "try X"
- findings.md builds a coherent narrative, not a flat list of results
- Negative results are recorded with what they rule out
- The agent updates its model when experiments contradict expectations
- Progress reports tell a research story with compelling visualizations

**Bad agent behavior:**
- Pure hyperparameter sweeps without interpretation
- findings.md is just experiment logs copy-pasted
- Agent never revisits its assumptions after failures
- Optimizing metrics without understanding why changes work

## When to Use vs Alternatives

**Use autoresearch when:**
- You have a research question explorable through experiments
- There's a measurable proxy metric for inner loop optimization
- The real contribution requires synthesis beyond the metric
- You want continuous autonomous research operation

**Use individual domain skills instead when:**
- You have a specific one-off task (train a model, run eval, write a paper)
- No iterative experimentation needed

## Common Issues

**Inner loop results don't make sense (numbers wildly off, baselines don't match expectations)**
This usually means Bring-Up was incomplete — your foundation has an undetected bug. Stop the Inner Loop. Go back to `experiments/_bringup/` and re-verify the relevant component end-to-end on its published benchmark. If it still doesn't reproduce, hand the discrepancy to `deep_thinker`: "Repo X claims metric Y on benchmark Z, I'm getting W. Here's my exact invocation. What's the most likely cause?"

**Inner loop stalls (no metric improvement)**
Run an outer loop. Is the metric the right one? Is the search space exhausted? Consider broadening or pivoting. Search literature for new approaches.

**Stuck and not making progress**
Don't keep trying random changes. Step back and use your **sounding boards**:
- `mcp__chatgpt__deep_thinker` for an immediate second opinion ("Here's where I'm stuck on {project}, here's what I've tried, what am I missing?"). Ask it to enumerate alternative framings, not just answers.
- `mcp__chatgpt__deep_researcher` if the stuck-ness suggests a literature gap (e.g., "I assumed nobody has done X — confirm or refute with a wide survey").
- Invoke `21-research-ideation/` brainstorming skills (which themselves call deep_thinker many times)
- Run an outer loop reflection
Being stuck means you need new information or a new perspective, not more experiments.

**Results contradict baseline expectations**
Investigate, don't ignore. Return to literature — your protocol might have an error, the published baseline may be wrong, or conditions differ. Update findings.md with what you learn.

**Agent loses context between ticks**
Ensure research-state.yaml and findings.md are updated after every action. These files are your memory across sessions.

**Can't find relevant papers**
Escalate by depth: (1) `mcp__chatgpt__deep_thinker` first — describe the gap and ask for 5–10 named papers with reasoning ("nothing comes up for X — is it called something else? are there adjacent literatures?"). (2) If still empty, `mcp__chatgpt__deep_researcher` for a full sweep including grey literature. (3) Then targeted retrieval: Exa MCP for broad search, Semantic Scholar for specific ML/AI paper lookup (`pip install semanticscholar`), arXiv for preprints (`pip install arxiv`). Check `20-ml-paper-writing` skill's `references/citation-workflow.md` for complete API code. Note: Google Scholar has no official API — use Semantic Scholar instead for programmatic search.

**No GPU available**
Use CPU and scale experiments down. Many research tasks (analysis, interpretability, small model training) run fine on CPU. Adjust experiment design to fit available compute rather than blocking.

**Experiments take longer than /loop interval**
Normal. On the next tick, check if it finished. If not, keep waiting or do something else useful (update notes, search papers). Adjust interval if needed.

**Not sure when to conclude**
Three questions: Do you have a strongly supported finding? Can you explain WHY it works? Would findings.md make a convincing paper abstract? If yes to all: conclude.

## Advanced Topics

- **Detailed agent continuity**: [references/agent-continuity.md](references/agent-continuity.md)
- **Progress presentation templates**: [references/progress-reporting.md](references/progress-reporting.md)
- **Complete skill routing**: [references/skill-routing.md](references/skill-routing.md)
