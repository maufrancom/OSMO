# E2E POC: Autonomous Agent Orchestrator

## Summary

Build an autonomous agent orchestrator that takes a natural language task, decomposes it into subtasks, executes them relentlessly across ephemeral compute sessions, communicates with humans asynchronously via object storage, and feeds intervention data back into the 5-layer framework. First task: Pydantic v1→v2.12.5 migration across the OSMO codebase.

## Context

The OSMO agent strategy defines a 5-layer AI-native framework (Context, Decision, Quality, Continuity, Meta-cognition) with DIF/LLM separation. The vertical slice is implemented: 8 DIF scripts, 5 knowledge docs, 4 service AGENTS.md files. What's missing is proof that this framework can drive a real, complex task end-to-end with minimal human intervention.

## Goals

1. Prove the 5-layer framework works on a real cross-cutting task
2. Demonstrate autonomous execution without babysitting
3. Measure human interventions (target: ≤2 for the entire migration)
4. Generate framework improvement patches from intervention analysis
5. Show the orchestrator is task-agnostic (Pydantic migration is just the first input)

## Non-Goals

- Building a production-grade web UI (static SPA is sufficient)
- Supporting multiple concurrent tasks (one task at a time for POC)
- Multi-user collaboration (single human operator for POC)
- Building a generic sample project (real OSMO task only)

---

## Architecture

### OSMO-Native Design

The orchestrator runs as an OSMO workflow. Each migration subtask is a child OSMO workflow. Git is the state passing mechanism. OSMO handles scheduling, container lifecycle, and monitoring.

```
┌─────────────────────────────────────────────────────────────┐
│  OSMO Workflow: "agent-orchestrator"                        │
│                                                             │
│  Task: orchestrator (long-running)                          │
│  ┌─────────────────────────────────────────────────────┐    │
│  │  Container: Claude Code + OSMO CLI + git             │    │
│  │                                                      │    │
│  │  1. git clone (with PAT) + checkout branch           │    │
│  │  2. Run discovery.sh (DIF)                           │    │
│  │  3. Plan subtask order (DIF)                         │    │
│  │  4. For each module:                                 │    │
│  │     a. Generate child workflow YAML                  │    │
│  │     b. osmo workflow submit migrate-{module}.yaml    │    │
│  │     c. osmo workflow query {id} (poll until done)    │    │
│  │     d. git pull (get child's changes)                │    │
│  │     e. Run quality gate on updated repo              │    │
│  │     f. If fail → revert, write question to S3        │    │
│  │  5. Final validation (full quality gate)             │    │
│  │  6. Generate intervention analysis                   │    │
│  │  7. Create PR via gh                                 │    │
│  └──────────┬──────────────────────────────────────────┘    │
│             │ osmo workflow submit (child workflows)         │
│             ▼                                                │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐       │
│  │ Child WF:    │  │ Child WF:    │  │ Child WF:    │       │
│  │ migrate      │  │ migrate      │  │ migrate      │       │
│  │ lib/utils    │  │ utils/job    │  │ service/core │       │
│  │              │  │              │  │              │       │
│  │ git clone    │  │ git clone    │  │ git clone    │       │
│  │ checkout br  │  │ checkout br  │  │ checkout br  │       │
│  │ Claude Code  │  │ Claude Code  │  │ Claude Code  │       │
│  │ commit+push  │  │ commit+push  │  │ commit+push  │       │
│  └──────────────┘  └──────────────┘  └──────────────┘       │
└─────────────────────────────────────────────────────────────┘
         │
         │  S3 (questions + interventions only)
         ▼
┌─────────────┐
│  Static SPA │  Human reads questions, submits answers
│  (Web UI)   │  Polls S3 for state
└─────────────┘
```

### System Components

1. **OSMO orchestrator workflow** — Long-running task with Claude Code + OSMO CLI + git. Submits child workflows, monitors them, coordinates.
2. **OSMO child workflows** — One per migration module. Clone repo, checkout branch, run Claude Code to migrate, commit + push.
3. **Git** — State passing mechanism between orchestrator and children. Branch = migration progress.
4. **S3** — Only for human interaction: questions, answers, intervention log. NOT for code state.
5. **Static web UI** — S3-hosted SPA. Shows progress, renders questions, accepts answers.

### Design Principles

- **OSMO-native**: The orchestrator IS an OSMO workflow. True dogfooding.
- **Git as state**: Code changes flow through git branches. No custom state layer for code.
- **No babysitting**: Orchestrator runs autonomously. Human checks in asynchronously via web UI.
- **Relentless execution**: Keep submitting child workflows. Only pause when blocked on human input.
- **Bounded self-correction**: 2 retry attempts per module before escalating to human.
- **Task-agnostic**: Swap the knowledge doc and workflow template for a different task.

---

## Orchestrator Core Loop

```
Start session → Load state from S3
    │
    ▼
Pending human answers? ──yes──► Incorporate, unblock subtasks
    │                                 │
    no                                │
    │◄────────────────────────────────┘
    ▼
Has a plan? ──no──► Discovery phase (DIF: scan codebase)
    │                 Planning phase (LLM: decompose, order, assess risk)
    yes
    │
    ▼
Pick next unfinished, unblocked subtask
    │
    ▼
Execute via sub-agent (LLM, scoped context)
    │
    ▼
Quality gate (DIF)
    │
    ├── pass → Mark done → More unblocked subtasks? → loop
    │
    └── fail → Self-correct (max 2)
                 └── still failing? → Write question → continue to next unblocked subtask
```

**Session lifecycle**:
- Cron or supervisor spawns sessions on a regular interval
- Human answer webhook triggers immediate session
- Session runs until: done, or all subtasks blocked, or compute timeout
- On exit: save state to S3

### Orchestrator Implementation

**Runtime**: OSMO workflow with a long-running orchestrator task. The container has Claude Code, OSMO CLI, and git installed.

**Entry point**: A bash script injected via `files:` in the OSMO workflow YAML. It runs the orchestrator loop: discovery → planning → submit child workflows → monitor → validate.

**Child workflow lifecycle**:
1. Orchestrator generates a workflow YAML for the module (from a template)
2. `osmo workflow submit migrate-{module}.yaml` — submits to OSMO
3. Child task: git clone, checkout branch, pull latest, run Claude Code with scoped prompt + knowledge doc
4. Claude Code migrates the module, commits, pushes to branch
5. Orchestrator: `osmo workflow query {id}` polls until done
6. Orchestrator: `git pull` to get child's changes
7. Orchestrator: runs quality gate on updated repo
8. If quality gate fails: `git revert HEAD`, write question to S3

**DIF/LLM dispatch**:
- Discovery: DIF (bash script — grep, scan, group)
- Planning: DIF (bash script — sort modules by dependency order)
- Child workflow generation: DIF (bash — template substitution)
- Child workflow execution: LLM (Claude Code inside child OSMO task)
- Quality gate: DIF (`quality-gate.sh`)
- Progress tracking: DIF (git log + `osmo workflow query`)
- Question generation: DIF (bash — structured JSON to S3)

**Concurrency control**: Sequential child workflows (POC scope). Orchestrator waits for each child to complete before submitting the next. No race conditions on git push.

### Git Strategy

- Orchestrator creates branch `agent/pydantic-v2-migration`
- Each child workflow commits to this branch with descriptive message
- Sequential execution ensures no merge conflicts
- Each commit is independently revertable
- The branch IS the progress log — `git log` shows exactly what's been migrated
- Final step: create PR from branch to main

### OSMO Credential Management

- GitHub PAT provided via OSMO `credentials:` field
- PAT mounted to a file path in the container
- Setup script configures git credential helper (same pattern as `cookbook/integration_and_tools/github/github.yaml`)

---

## Object Storage Schema

### Directory Structure

```
s3://osmo-agent/{task-id}/
├── task.json              # Original prompt + decomposed plan
├── state.json             # Current orchestrator state
├── questions/
│   └── q-NNN.json         # Agent questions with context + options
├── subtasks/
│   └── st-NNN.json        # Per-subtask state + quality results
├── interventions.json     # Every human interaction, categorized
└── artifacts/
    ├── st-NNN.patch       # Code changes per subtask
    ├── st-NNN-quality.json # Quality gate results
    └── framework-improvements/  # Generated framework patches
```

### Schema Design: Strict Envelope, Fluid Content

- **Strict fields** (DIF-parseable): `id`, `status`, `type`, `timestamps`, `phase`, `current_subtask`. Validated by JSON Schema. The orchestrator and web UI depend on these.
- **Fluid fields** (LLM-generated): `context`, `question`, `reasoning`, `options[].label`, `framework_improvement`. Free-form strings rendered as-is. No schema constrains what the agent can express.

### `task.json`

```json
{
  "id": "task-001",
  "prompt": "Migrate from Pydantic v1 to v2.12.5, no regressions, full advantage of v2",
  "created": "2026-03-19T10:00:00Z",
  "status": "in_progress",
  "plan": {
    "phases": ["discovery", "planning", "execution", "validation"],
    "subtasks": ["st-001", "st-002", "..."],
    "dependency_graph": {"st-002": ["st-001"], "...": "..."}
  }
}
```

### `state.json`

```json
{
  "current_phase": "execution",
  "current_subtask": "st-003",
  "completed": ["st-001", "st-002"],
  "blocked": ["st-013"],
  "pending_questions": ["q-002"],
  "last_session": "2026-03-19T14:30:00Z",
  "sessions_count": 4,
  "total_interventions": 1
}
```

### `questions/q-NNN.json`

```json
{
  "id": "q-001",
  "status": "pending | answered",
  "asked": "2026-03-19T11:00:00Z",
  "context": "lib/utils/login.py uses BaseModel with Config inner class for 4 models...",
  "question": "Should I use model_config = ConfigDict() or keep backward-compatible Config inner class?",
  "options": [
    {"key": "A", "label": "Full v2 (ConfigDict)", "reasoning": "Clean, uses v2 idioms"},
    {"key": "B", "label": "Compatibility shim", "reasoning": "Less churn, v1 patterns remain"}
  ],
  "answer": {"key": "A", "by": "human", "at": "2026-03-19T12:15:00Z"},
  "impact": "Applied to all 212 BaseModel subclasses"
}
```

### `interventions.json`

```json
{
  "interventions": [
    {
      "id": "int-001",
      "question_id": "q-001",
      "timestamp": "2026-03-19T12:15:00Z",
      "category": "design_decision",
      "subtask": "st-003",
      "what_happened": "Agent couldn't determine migration style preference",
      "why_blocked": "architecture-intent.md has no guidance on migration patterns",
      "human_answer": "Always use idiomatic v2",
      "resolution_time": "1h15m",
      "avoidable": true,
      "framework_fix": {
        "type": "knowledge_doc",
        "target": "docs/agent/architecture-intent.md",
        "change": "Add: For library/framework migrations, prefer idiomatic target version over compatibility shims"
      }
    }
  ],
  "summary": {
    "total": 1,
    "avoidable": 1,
    "categories": {"design_decision": 1, "ambiguity": 0, "bug": 0, "failure": 0, "steering": 0}
  }
}
```

---

## Human Interaction

### Async Protocol

The orchestrator and human are never online at the same time by design.

| Agent Action | Human Action |
|---|---|
| Writes question with context + options to S3 | Reads question via web UI |
| Continues working on unblocked subtasks | Answers when convenient |
| Picks up answer on next session start | Gets notified of progress |
| Logs intervention for framework improvement | Reviews intervention log |

### Static Web UI

Single HTML file hosted on S3. No framework, no build step, no backend.

**Shows**:
- Task name and status
- Progress bar (completed/total subtasks)
- Pending questions with clickable option buttons + free-text fallback
- Recent activity log
- Intervention count and summary

**Reads**: `state.json`, `questions/*.json`, `interventions.json` via S3 GET (polling every 30s)

**Writes**: Answer field back to question file via presigned URL or tiny Lambda

**Auth**: Presigned URLs with short TTL, or API Gateway + Lambda with basic auth.

---

## Pydantic Migration: First Task

### Scope

- **Current version**: pydantic==1.10.26 (in `src/requirements.txt`)
- **Target version**: pydantic==2.12.5
- **Files affected**: ~68-72 (estimate; discovery DIF will produce authoritative count)
- **BaseModel subclasses**: 212 (across 40 files)
- **Total Pydantic usages**: 657
- **V1 migration targets**: 38 `.dict()` calls (across 23 files), 19 `class Config:` inner classes (across 13 files)
- **Heaviest modules**: `utils/connectors/postgres.py` (85 usages, 42 models), `service/core/workflow/objects.py` (49), `utils/backend_messages.py` (38), `utils/job/task.py` (34)
- **V1-specific patterns**: No `@validator` or `@root_validator` found (good news — fewer breaking patterns)

### Execution Phases

**Discovery (DIF)**:
- Scan `requirements.txt` → confirm current version
- Grep all Pydantic imports → group by module
- Detect v1 patterns: `Config` inner class, `.dict()`, `.json()`, `Field(...)`, `Optional` usage
- Build dependency graph (leaf modules first, shared libs last)
- Output: populated `task.json` with subtask list

**Planning (LLM)**:
- Read Pydantic v2 migration guide + `docs/agent/architecture-intent.md`
- Order subtasks: leaf modules first → shared libs → core services (tests stay green incrementally)
- Flag high-risk modules
- Produce subtask definitions with scope estimates

**Execution (per subtask, sub-agent)**:
- Each sub-agent gets scoped context: target files + migration knowledge doc + learned decisions from answered questions
- Apply v1→v2 transformations
- Run `scripts/agent/lint-fast.sh` on changed files
- Run module-level tests
- Pass → produce patch, mark done
- Fail → self-correct (2 tries) → still failing → write question, move on

**Validation (DIF)**:
- Run full `scripts/agent/quality-gate.sh` across entire codebase
- Verify no v1 patterns remain (grep for `.dict()`, `Config:` inner class, etc.)
- Run integration tests
- Produce final report

### What Makes This a Framework Proof

The orchestrator doesn't know it's doing a Pydantic migration. It executes a generic loop: prompt → discover → plan → execute subtasks → quality gate → done. The Pydantic-specific knowledge lives in a pluggable knowledge doc. Swap it for "add OpenTelemetry tracing" and the same orchestrator handles it.

---

## Intervention Feedback Loop

### Categories

| Category | Meaning | Framework Fix Type |
|---|---|---|
| **design_decision** | Agent lacked a rule | Add to architecture-intent.md or decision-tree.md |
| **ambiguity** | Conflicting signals in docs | Clarify in knowledge docs |
| **bug** | Broken code, self-correction failed | Add pattern to task knowledge doc |
| **failure** | Quality gate failed exhaustively | Improve quality gate or add pre-check |
| **steering** | Human wanted different direction | May not be avoidable (genuine judgment) |

### Post-Task Analysis

After task completion, the orchestrator:
1. Reads `interventions.json`
2. Groups avoidable interventions by `framework_fix.type`
3. Generates concrete patches to framework files (knowledge docs, DIF scripts, AGENTS.md)
4. Writes patches to `artifacts/framework-improvements/`
5. These become a PR — the framework improves itself

---

## Continuity

Git is the continuity mechanism. The orchestrator branch (`agent/pydantic-v2-migration`) contains the full history of migration progress. Each child workflow starts by cloning and pulling the latest branch state. If the orchestrator task crashes and restarts, it reads `git log` to determine which modules have already been migrated, and resumes from where it left off.

S3 state (`questions/`, `interventions.json`) supplements git for human interaction data that doesn't belong in the repo.

## Runtime

- **Orchestrator**: OSMO workflow task with Claude Code + OSMO CLI + git
- **Child tasks**: OSMO workflow tasks with Claude Code + git
- **DIF scripts**: Bash — run inside orchestrator container
- **Code state**: Git branch (pushed to remote)
- **Human interaction state**: S3 (questions, interventions)
- **Web UI**: Static HTML/JS on S3
- **Credentials**: GitHub PAT via OSMO `credentials:` field

---

## Success Criteria

### Must-Have (POC passes)

1. Pydantic v1→v2 migration complete across all 68 files
2. All existing tests pass — zero regressions
3. No v1 patterns remaining in codebase (`.dict()`, `Config:` inner class, v1 imports)
4. Intervention log with categorization and avoidability analysis produced
5. Framework improvement patches generated from intervention data
6. Orchestrator ran autonomously without babysitting (human only answered async questions)

### Aspirational (thesis validated)

7. Total human interventions ≤ 2 for the entire migration
8. Orchestrator demonstrably task-agnostic (could accept a different task prompt with a different knowledge doc)

### Success With Learning (POC still valuable even if aspirational targets missed)

9. If interventions > 2 but ≤ 5: POC succeeds if all interventions are categorized, avoidability assessed, and framework patches generated. The feedback loop working is more important than hitting the target on the first task.
10. Task-agnosticism is a design goal to validate, not a guaranteed property. The discovery phase will contain Pydantic-specific logic. The goal is to minimize task-specific code and maximize reusable orchestration. A future task (e.g., "add OpenTelemetry") would validate how much orchestrator code is reusable.

---

## Resolved Questions

- **Q10**: Session scheduling — **OSMO manages it**. The orchestrator is a long-running OSMO task. No cron needed. If it crashes, OSMO can restart it, and it resumes from git state.
- **Q11**: Sub-agent isolation — **OSMO workflow isolation**. Each child workflow runs in its own container. Strongest possible isolation — separate pod, separate filesystem, separate process.
- **Q12**: Subtask execution — **Sequential child workflows**. Orchestrator submits one child at a time, waits for completion, pulls changes, validates, then submits next. No merge conflicts.
- **Q13**: State passing — **Git**. Code state flows through git branch. No custom S3 state layer for code. S3 only for human interaction (questions, interventions).

---

## Decisions Made

| # | Decision | Rationale |
|---|---|---|
| D25 | OSMO-native orchestrator | Orchestrator runs as OSMO workflow. True dogfooding. OSMO handles compute, scheduling, credentials. |
| D26 | Git as state, S3 for questions only | Code state flows through git branch. S3 only for human interaction. No custom state layer. |
| D27 | Strict envelope, fluid content schema | DIF/LLM separation applied to data. Structure for routing, freedom for expression. |
| D28 | Intervention feedback loop | Every interaction logged, categorized, fed back as framework improvement. |
| D29 | Relentless execution | Keep going on unblocked subtasks. Only pause when fully blocked. |
| D30 | Pydantic v1→v2 as first task | Cross-cutting, clear success criteria, exercises all 5 layers. |
| D31 | Static web UI for POC | Fastest path to demo. Orchestrator is the product, not the UI. |
