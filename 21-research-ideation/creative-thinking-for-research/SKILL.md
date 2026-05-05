---
name: creative-thinking-for-research
description: Applies cognitive science frameworks for creative thinking to CS and AI research ideation. Use when seeking genuinely novel research directions by leveraging combinatorial creativity, analogical reasoning, constraint manipulation, and other empirically grounded creative strategies.
version: 1.1.1
author: Orchestra Research
license: MIT
tags: [Creative Thinking, Research Ideation, Analogical Reasoning, Problem Reformulation, Cognitive Science, Deep Thinker, Deep Researcher, Parallel Sub-Agents]
dependencies: []
---

# Creative Thinking for Research

Eight empirically grounded frameworks from cognitive science, applied to computer science and AI research. Unlike ad-hoc brainstorming, each framework here is backed by decades of creativity research — from Koestler's bisociation to Kauffman's adjacent possible. They target distinct cognitive operations: combining, reformulating, analogizing, constraining, inverting, abstracting, exploring boundaries, and holding contradictions.

## When to Use This Skill

- Generating genuinely novel ideas, not incremental extensions of prior work
- Feeling trapped in a local optimum of thinking within a single subfield
- Wanting to systematically apply creativity heuristics rather than waiting for inspiration
- Preparing for a research retreat or PhD-level ideation session
- Bridging between fields and seeking structural (not superficial) connections

**Do NOT use this skill when**:
- You need structured project-level brainstorming workflows (use `brainstorming-research-ideas`)
- You have a well-defined problem and need execution help (use domain-specific skills)
- You need a literature survey (use `scientific-skills:literature-review`)

**Relationship to Brainstorm skill**: The brainstorm skill provides operational workflows (diverge → converge → refine) and practical filters. This skill provides the deeper cognitive engines that power creative leaps. Use them together: creative-thinking to generate raw insight, brainstorm to structure and evaluate it.

---

## Sounding Boards: `deep_thinker` and `deep_researcher` (NON-NEGOTIABLE)

Creative thinking without an external sparring partner devolves into self-confirming noise. **Every framework below has at least one moment where you must hand off to `deep_thinker`** — the entire point of these cognitive frameworks is to expose your reasoning to forces outside your own head, and `deep_thinker` is the most accessible such force.

| Tool | Latency | When |
|---|---|---|
| **`mcp__chatgpt__deep_thinker`** | ~5–10 min | Validate that a bisociation is structural not surface; confirm an analogy preserves causal structure; pressure-test a problem reformulation; check whether a constraint is truly hidden or just under-acknowledged; rate whether a Janusian synthesis is a real synthesis or a compromise. **Multi-turn pushback is encouraged** — if its first answer is shallow, push: "go deeper, name papers, give me failure modes." |
| **`mcp__chatgpt__deep_researcher`** | ~1–2 hr | Use ONCE before a deep creative session to map the field's existing analogies, prior reformulations, and the current "adjacent possible" enablers (Framework 7). Avoid re-running for every framework. |

**Briefing well**: dump full domain context, state your candidate idea or analogy, ask for SPECIFIC outputs ("name 5 papers", "rate structural fidelity 1–5 with reasons", "give me 3 counter-examples"). Don't be brief — these tools reward dense prompts.

**Calibration**: if you finish a creative session having called `deep_thinker` fewer than 5 times, you ran too shallow. The frameworks here are designed to be paired with external reasoning.

**PARALLELIZE via sub-agents**. When validating K analogies or K bisociation cells, spawn K sub-agents (Agent tool) in one message — each calling `deep_thinker` on one candidate. Validation is embarrassingly parallel; serial calls waste wall-clock. Same applies to `deep_researcher` for landscape maps: split into 3–6 sub-topics and run sub-agents in parallel.

---

## Framework 1: Combinatorial Creativity (Bisociation)

Novel ideas arise from combining existing concepts in unexpected ways. Arthur Koestler called this **bisociation** — connecting two previously unrelated frames of reference, as distinct from routine association within a single frame.

**Why it works**: Meta-research consistently shows that breadth of knowledge is a precursor to creative output. People who read across disciplines produce more novel work. The combination itself is the creative act.

**In CS Research**:
- Biological evolution → optimization (genetic algorithms)
- Game theory → networking (mechanism design for routing)
- Statistical physics → machine learning (Boltzmann machines, energy-based models)
- Linguistics → programming (type theory, formal grammars)

**Systematic Bisociation Workflow**:

1. **Select two domains** you have at least passing familiarity with
2. **List core primitives** in each domain (5-10 fundamental concepts per domain)
3. **Create a cross-product matrix**: row = concepts from Domain A, column = concepts from Domain B
4. **For each cell**, ask: "What would it mean to apply A's concept to B's problem?"
5. **Filter**: Which combinations produce a non-trivial, testable research question?
6. **Validate structural depth**: Is the connection mechanistic or merely metaphorical?

**Cross-Product Example**:

| | Caching | Load Balancing | Fault Tolerance |
|---|---------|---------------|-----------------|
| **Natural Selection** | Evict least-fit entries | Adaptive allocation via fitness | Population-level redundancy |
| **Immune Memory** | Learned threat signatures | Distributed detection | Self/non-self discrimination |
| **Symbiosis** | Cooperative prefetching | Mutualistic resource sharing | Co-dependent resilience |

**Quality Test**: A strong bisociation is not a surface metaphor ("the network is like a brain") but a structural mapping where the mechanism transfers ("attention mechanisms implement a form of selective gating analogous to cognitive attention filtering").

**Self-Check**:
- [ ] Is the connection structural (mechanisms map) or merely verbal (labels map)?
- [ ] Does the combination generate testable predictions?
- [ ] Would an expert in both fields find the connection non-obvious but sound?

**`deep_thinker` checkpoint**: For each candidate cell from your matrix, send the bisociation: "I'm proposing to apply {concept A from domain X} to {problem B in domain Y}. Is this a structural mapping (mechanisms transfer) or surface metaphor (labels match but mechanisms diverge)? Name 1–2 prior attempts at similar transfers if any. Rate structural fidelity 1–5." Discard surface metaphors immediately — they look creative but produce thin papers.

---

## Framework 2: Problem Reformulation (Representational Change)

Gestalt psychologists identified that breakthroughs often come not from solving the problem as stated, but from **re-representing the problem itself**. Kaplan and Simon's work on insight shows that changing the problem space — the constraints, the abstraction level, the formalism — is often where creativity lives.

**The Key Shift**: From "How do I solve this problem?" to "Am I even thinking about this problem correctly?"

**Reformulation Strategies**:

| Strategy | Example |
|----------|---------|
| **Change the objective** | "Make the algorithm faster" → "Eliminate the need for this computation" |
| **Change the formalism** | Graph problem → linear algebra problem (spectral methods) |
| **Change the granularity** | Per-token prediction → per-span prediction |
| **Change the agent** | "How should the model learn?" → "How should the data teach?" (curriculum learning) |
| **Change the timescale** | Real-time optimization → amortized inference |
| **Invert the direction** | Forward simulation → inverse problem (learning from observations) |

**Workflow**:

1. State your current problem in one sentence
2. Identify the **hidden assumptions** in that statement:
   - What formalism are you using? (Could you use a different one?)
   - What is the objective? (Is it the right objective?)
   - What level of granularity? (Could you go coarser or finer?)
   - Who is the agent? (Could you shift perspective?)
3. For each assumption, **generate the alternative**: "What if [opposite assumption]?"
4. For each alternative, ask: "Does this reformulation make the problem easier, harder, or different in a useful way?"
5. A reformulation that makes a hard problem easy is often a publishable insight on its own

**Classic CS Examples**:
- **PageRank**: Reformulated "find important web pages" from content analysis to graph eigenvalue problem
- **Dropout**: Reformulated "prevent overfitting" from regularization to approximate ensemble
- **Attention**: Reformulated "handle long sequences" from remembering everything to selectively querying

**`deep_thinker` checkpoint**: After step 3, send your reformulations: "Original problem: {X}. I've generated 3 reformulations: {list}. For each, (a) has someone already attempted this reformulation? name them. (b) does the reformulation actually change the difficulty class, or just rename it? (c) which is most likely to yield a publishable insight?" This separates real reformulation from cosmetic rephrasing.

---

## Framework 3: Analogical Reasoning (Structure-Mapping)

Dedre Gentner's **structure-mapping theory** and Kevin Dunbar's studies of real scientists show that analogy is the core engine of scientific creativity. The critical finding: surface-level analogies are common but weak; **structural or relational analogies** — where the deep causal/relational structure maps across domains — produce the most powerful insights.

**Dunbar's Finding**: In the most successful labs, analogies from distant domains drove the most important discoveries. Nearby analogies refined ideas; distant analogies generated them.

**Levels of Analogical Depth**:

| Level | Description | Value | Example |
|-------|-------------|-------|---------|
| **Surface** | Things look similar | Low | "A neural network is like a brain" |
| **Relational** | Relationships between entities match | Medium | "Attention allocation in models parallels resource allocation in economics" |
| **Structural** | Deep causal mechanisms map | High | "Diffusion models reverse a thermodynamic process; the math of non-equilibrium stat-mech directly applies" |

**Structure-Mapping Workflow**:

1. **Describe your problem** using only relational/causal language (strip domain-specific nouns)
   - Bad: "We need to improve transformer attention efficiency"
   - Good: "We have a system that must selectively aggregate information from a large set, where relevance is context-dependent and the cost scales quadratically with set size"
2. **Search for structural matches**: What other systems selectively aggregate from large sets?
   - Database query optimization, visual attention in neuroscience, information retrieval, resource allocation
3. **Pick the most distant match** with genuine structural fidelity
4. **Map the solution mechanism**: How does the source domain solve this?
5. **Transfer and adapt**: What changes when you bring that mechanism into your domain?
6. **Generate predictions**: The analogy should tell you something you didn't already know

**Validation Checklist**:
- [ ] Does the mapping preserve causal/relational structure (not just labels)?
- [ ] Can I identify at least one prediction the analogy makes in my domain?
- [ ] Would an expert in the source domain confirm the mechanism is correctly understood?
- [ ] Is the analogy non-obvious to my target audience?

**`deep_thinker` checkpoint** (use this for EACH candidate analogy — Dunbar's data shows distant analogies require expert validation):
- Turn 1: "I claim {source domain mechanism} is structurally analogous to {target domain problem}. Critique: where does the mapping break? What's the strongest disanalogy?"
- Turn 2: "Steelman the analogy: assuming I can patch the disanalogies, what concrete prediction does it make in the target domain that current methods don't?"
- Turn 3: "Has any prior paper used this analogy explicitly? Name them, even if from very distant fields." If 0 hits → likely novel; if many hits → check whether your variant adds anything.

---

## Framework 4: Constraint Manipulation (Boden's Framework)

Margaret Boden's framework distinguishes three forms of creativity based on how they interact with constraints:

| Type | Operation | CS Example |
|------|-----------|------------|
| **Exploratory** | Search within the existing conceptual space | Hyperparameter tuning, architecture search within a fixed paradigm |
| **Combinational** | Combine elements from different spaces | Multi-task learning, neuro-symbolic methods |
| **Transformational** | Change the rules of the space itself | Dropping the assumption that training requires labels (self-supervised learning) |

**Transformational creativity is the rarest and highest-impact.** It happens when you change what is even considered a valid solution.

**Constraint Analysis Workflow**:

1. **List the constraints** of your current approach (5-10 constraints):
   - Computational: "Must fit in GPU memory"
   - Methodological: "Requires labeled data"
   - Architectural: "Uses fixed-length context"
   - Evaluative: "Measured by accuracy on benchmark X"
2. **Classify each constraint**:
   - **Hard**: Physically or logically necessary (cannot violate)
   - **Soft**: Convention or historical accident (can question)
   - **Hidden**: Not stated but implicitly assumed (most fertile for innovation)
3. **For each soft/hidden constraint**, ask:
   - What if we relaxed it? (streaming algorithms from relaxing "fits in memory")
   - What if we tightened it? (efficiency research from tightening compute budgets)
   - What if we replaced it with a different constraint entirely?
4. **The most productive move** is often exposing and dropping a hidden constraint

**Classic Examples of Constraint Transformation**:
- "Data must fit in memory" → dropped → streaming algorithms, external memory
- "Training requires human labels" → dropped → self-supervised learning
- "Models must be deterministic" → dropped → variational methods, diffusion
- "Inference must happen in one pass" → dropped → iterative refinement, chain-of-thought

**`deep_thinker` checkpoint**: Send your constraint list with classifications. Ask: "Audit my hard/soft/hidden labels. Specifically: (1) which constraints I called 'hard' are actually 'soft' under modern conditions? (2) are there hidden constraints I haven't named? (3) for each soft/hidden one, has someone already published the result of relaxing it? name them." Hidden constraints are the most fertile and the hardest to spot alone — this is where `deep_thinker` earns its keep.

---

## Framework 5: Negation and Inversion

Take a core assumption in your field and negate it. This is formalized in De Bono's lateral thinking and the **TRIZ methodology** from engineering.

**The Pattern**: "What if [widely held assumption] is wrong, unnecessary, or invertible?"

**Systematic Negation Workflow**:

1. **List 5-10 core assumptions** in your subfield (the things "everyone knows")
2. **Negate each one** and ask: What system would you build?
3. **Evaluate each negation**:
   - Incoherent → discard
   - Already explored → check if conditions have changed (see brainstorm skill, Framework 5)
   - Unexplored and coherent → potential research direction

**Negation Hall of Fame in CS**:

| Assumption | Negation | Result |
|-----------|----------|--------|
| "We need strong consistency" | What if we don't? | Eventual consistency, CRDTs |
| "We need exact answers" | What if approximate is fine? | Sketches, LSH, approximate nearest neighbors |
| "Labels are necessary" | What if we learn without them? | Self-supervised learning, contrastive methods |
| "More parameters = more compute" | What if we don't use all parameters? | Mixture of Experts, sparse models |
| "Training and inference are separate" | What if the model keeps learning? | Online learning, test-time training |
| "Errors must be prevented" | What if we embrace and correct them? | Speculative decoding, self-correction |

**TRIZ-Inspired Principles for CS**:

| TRIZ Principle | CS Application |
|---------------|----------------|
| **Inversion** | Reverse the process (generative vs. discriminative) |
| **Segmentation** | Break monolithic into modular (microservices, mixture of experts) |
| **Merging** | Combine separate steps (end-to-end learning) |
| **Universality** | One component serves multiple functions (multi-task models) |
| **Nesting** | Place one system inside another (meta-learning) |
| **Dynamization** | Make static things adaptive (dynamic architectures, adaptive computation) |

---

## Framework 6: Abstraction and Generalization Laddering

Moving up and down the abstraction ladder is a fundamental creative act. Polya's heuristics formalize this: *"Can you solve a more general problem? A more specific one? An analogous one?"*

**Three Moves**:

| Move | Question | Outcome |
|------|----------|---------|
| **Generalize** | "Is my solution a special case of something broader?" | Framework papers, unifying theories |
| **Specialize** | "What happens when I add extreme constraints?" | Niche applications, surprising edge cases |
| **Analogize** | "Where else does this abstract pattern appear?" | Cross-domain transfer (see Framework 3) |

**Generalization Workflow**:
1. State your specific result
2. Replace each specific element with a variable: "ResNet works for ImageNet" → "Architecture X works for distribution Y"
3. Ask: Under what conditions does this hold? What is the general principle?
4. If the general principle is novel → that is the contribution

**Specialization Workflow**:
1. Take a general method
2. Add extreme constraints: tiny data, huge dimensionality, adversarial inputs, real-time requirements
3. Ask: Does the method still work? If not, why not?
4. The failure case often reveals the method's true assumptions

**When to Generalize vs. Specialize**:
- Generalize when you have results but no explanation
- Specialize when you have theory but no grounding
- Analogize when you are stuck in either direction

---

## Framework 7: The Adjacent Possible (Kauffman / Johnson)

Stuart Kauffman's concept, popularized by Steven Johnson: innovation happens at the boundary of what is currently reachable — the **adjacent possible**. New ideas become thinkable once their prerequisites exist. This explains why simultaneous independent discovery is so common — multiple people reach the same boundary.

**Practical Implication**: Map what has recently become possible and explore the space those enablers open.

**Adjacent Possible Mapping Workflow**:

1. **List recent enablers** (last 1-3 years):
   - New hardware capabilities (longer context, faster inference, new accelerators)
   - New datasets or benchmarks
   - New open-source tools or frameworks
   - New theoretical results
   - New regulatory or social conditions
2. **For each enabler, ask**: "What was previously impossible or impractical that this now permits?"
3. **Combine enablers**: The most powerful adjacent possibles arise from the intersection of multiple new enablers
4. **Check for competition**: If many people can see the same adjacent possible, speed or a unique angle matters

**Current Adjacent Possibles (2025-2026)**:

| Enabler | Newly Possible |
|---------|---------------|
| 1M+ token context windows | Full-codebase reasoning, book-length analysis |
| Inference cost drops (100x in 2 years) | Real-time agentic loops, always-on AI assistants |
| Open-weight models at GPT-4 level | Reproducible research on frontier capabilities |
| Multimodal models (vision + language + audio) | Unified perception-reasoning systems |
| Synthetic data at scale | Training data for domains with no natural data |
| Tool-using models | Research automation, self-improving systems |

**Timing Signal**: If your idea requires technology that doesn't exist yet, it's beyond the adjacent possible — park it. If your idea could have been done 5 years ago, someone probably did — check the literature. The sweet spot is ideas that became feasible in the last 6-18 months.

---

## Framework 8: Janusian and Dialectical Thinking

Albert Rothenberg's studies of eminent creators found that **holding two contradictory ideas simultaneously** is a hallmark of creative thinking. Named after Janus, the two-faced Roman god, this mode of thinking doesn't resolve contradictions by choosing a side — it generates new frameworks that transcend the opposition.

**In CS**: The most influential results often emerge from tensions previously thought irreconcilable.

| Contradiction | Resolution | Impact |
|--------------|------------|--------|
| Consistency AND Availability (distributed systems) | CAP theorem: formalized the trade-off, then Raft/CRDTs found practical middle grounds | Foundation of distributed systems theory |
| Security AND Usability | Zero-knowledge proofs: prove knowledge without revealing it | Enabled private computation |
| Expressiveness AND Tractability | Probabilistic programming: express complex models, automate inference | New programming paradigm |
| Memorization AND Generalization | Grokking: models memorize first, then generalize with more training | New understanding of learning dynamics |
| Compression AND Quality | Neural codecs that compress beyond information-theoretic limits via learned priors | Redefined compression research |

**Dialectical Thinking Workflow**:

1. **Identify a binary** in your field: A vs. B (two approaches, goals, or paradigms treated as opposites)
2. **Resist choosing a side**. Instead ask:
   - "What would a system look like that achieves both A and B?"
   - "Under what conditions is the A-B trade-off not fundamental?"
   - "Is the opposition an artifact of how we formalized the problem?"
3. **Seek synthesis**: The resolution often requires a new abstraction that reframes the relationship
4. **Test the synthesis**: Can you demonstrate empirically that both goals are achievable?

**Self-Check**:
- [ ] Am I holding the contradiction genuinely (not prematurely resolving it)?
- [ ] Is the synthesis a new idea, not just a compromise (splitting the difference)?
- [ ] Does the resolution change how people think about the problem, not just the solution?

**`deep_thinker` checkpoint**: Janusian thinking is the most prone to self-deception (you can imagine you've synthesized when you've just rephrased). Send: "I claim a synthesis between {A} and {B} via {mechanism}. Three diagnostic questions: (1) is this a true synthesis or a compromise / Pareto-point selection? (2) what would falsify the synthesis empirically? (3) which papers tackled the same A-vs-B tension — did any reach a similar synthesis?" Iterate until the answer is unambiguous.

---

## Combining Frameworks: A Creative Thinking Protocol

These frameworks are most powerful in combination. Here is a systematic protocol for a deep creative thinking session.

**Pre-session (one-time)**: call `mcp__chatgpt__deep_researcher` for a landscape map of existing analogies, prior reformulations, and current "adjacent possible" enablers in your area. Save to `literature/_deep_research_<area>_<date>.md`. This grounds every framework below.

### Phase 1: Map the Space (15 min + `deep_thinker` calls)
1. **Constraint Manipulation** (F4): List constraints, classify hard/soft/hidden → `deep_thinker` to audit your classification (see F4 checkpoint)
2. **Adjacent Possible** (F7): List recent enablers → `deep_thinker`: "Which of these enablers has the most under-explored adjacent possibles right now?"

### Phase 2: Generate Disruptions (30 min, `deep_thinker` between each step)
3. **Negation** (F5): Negate 3 soft/hidden constraints → `deep_thinker`: "for each negation, has it been tried? what failed?"
4. **Bisociation** (F1): Cross-product matrix → `deep_thinker` checkpoint validates structural fidelity
5. **Problem Reformulation** (F2): 3 reformulations → `deep_thinker` checkpoint separates real reformulation from rephrasing

### Phase 3: Deepen Promising Leads (30 min, `deep_thinker` per lead)
6. **Analogical Reasoning** (F3): Multi-turn `deep_thinker` round per analogy (see F3 checkpoint — 3 turns)
7. **Abstraction Laddering** (F6): `deep_thinker`: "for each rung, name the canonical paper if any; flag empty rungs as candidates"
8. **Janusian Thinking** (F8): `deep_thinker` synthesis-vs-compromise audit (see F8 checkpoint)

### Phase 4: Evaluate (15 min + final `deep_thinker` adversarial round)
Apply the two-sentence test (from the brainstorm skill):
> "**[Domain] currently struggles with [problem] because [reason].** We [approach] by [mechanism], which works because [insight]."

Then run a final `deep_thinker` adversarial pass: "Here are my surviving ideas. Be a hostile NeurIPS reviewer. Which would you reject and why? Which would you champion?" Any idea that survives the test AND the reviewer round is worth pursuing.

**Total `deep_thinker` calls in a full session**: typically 10–15. If you ran fewer than 8, you skipped checkpoints.

---

## Common Creative Blocks and Unblocking Strategies

| Block | Symptom | Framework to Apply |
|-------|---------|-------------------|
| **Fixation** | Cannot stop thinking about the problem one way | Problem Reformulation (F2) — force a different representation |
| **Tunnel vision** | All ideas come from the same subfield | Bisociation (F1) or Analogical Reasoning (F3) — import from elsewhere |
| **Self-censoring** | Dismissing ideas as "too weird" before exploring | Negation (F5) — weird is the point; evaluate after generating |
| **Incrementalism** | Every idea is "+2% on benchmark X" | Constraint Manipulation (F4) — change the rules, not the parameters |
| **Analysis paralysis** | Too many options, cannot commit | Adjacent Possible (F7) — what is feasible right now? |
| **False dichotomy** | Stuck choosing between two approaches | Janusian Thinking (F8) — seek synthesis, not selection |

---

## Usage Instructions for Agents

When a researcher asks for help with creative thinking or novel ideation:

0. **Pre-session landscape scan**: invoke `mcp__chatgpt__deep_researcher` if no recent survey exists for the area. Save the report to `literature/`.
1. **Assess the block**: What kind of thinking are they stuck in? (See Common Creative Blocks table)
2. **Select 2-3 frameworks** based on the block type
3. **Walk through each framework interactively**. **At every framework's `deep_thinker` checkpoint, actually call `mcp__chatgpt__deep_thinker`.** These are not decoration. Distant analogies and structural mappings cannot be self-validated reliably; external reasoning is the corrective force.
4. **Push for structural depth**: If `deep_thinker` says an analogy is surface-level, probe deeper — don't accept your first idea
5. **Maintain a running list** of all generated ideas, even unusual ones. Save important `deep_thinker` exchanges to `literature/_deep_thinker_<topic>_<date>.md`
6. **Apply the two-sentence test** to candidates that survive exploration
7. **Final adversarial `deep_thinker` round** before declaring winners — at least 3 turns of pushback
8. **Hand off to the brainstorm skill** for systematic evaluation (diverge → converge → refine)

**Sounding-board call budget**: 8–15 `deep_thinker` calls per deep creative session, 0–1 `deep_researcher` (Phase 0 only).

**Key Principles**:
- **Call `deep_thinker` aggressively** — creative thinking without external pushback is self-confirming
- Generative mode first, evaluative mode second — do not filter prematurely
- Distant analogies are more valuable than nearby ones, but require more validation (this is exactly where `deep_thinker` is non-negotiable)
- The researcher's domain expertise is essential — the agent provides the cognitive scaffolding, `deep_thinker` provides external validation, the researcher provides domain truth
- Encourage the researcher to sit with contradictions rather than resolve them quickly
