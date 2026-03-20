# Implementation Architecture: From Framework to Code

This document maps the 5-layer AI-native framework to concrete implementations -- first for OSMO development (the vertical slice), then for Physical AI pipelines (the product).

---

## 1. Layer Implementations for OSMO Development (Vertical Slice)

### Context Layer

| Component | Type | Purpose |
|-----------|------|---------|
| `AGENTS.md` (root) | File | Top-level map, coding standards, codebase structure |
| `src/service/core/AGENTS.md` | File | Core service context: routes, auth, workflow, config |
| `src/lib/AGENTS.md` | File | Library context: storage SDK, dataset manager, utils |
| `src/runtime/AGENTS.md` | File | Go runtime context: ctrl/user/rsync, IPC, data handling |
| `docs/agent/decision-tree.md` | File | Given a task type, which files/modules to read first |
| `docs/agent/cross-service-impact.md` | File | Which services are affected by changes in shared code |
| `scripts/agent/route-context.sh` | DIF | Given a file path, output relevant AGENTS.md and docs |

**How it works**: Agent receives task -> reads decision-tree.md to identify task type -> route-context.sh returns relevant files -> agent reads those files -> agent has focused context for the task.

### Decision Layer

| Component | Type | Purpose |
|-----------|------|---------|
| `docs/agent/architecture-intent.md` | File | Why the system is designed this way -- for ambiguous cases |
| `scripts/agent/check-decisions.sh` | DIF | Verify changes respect architectural boundaries |
| Existing linters (ruff, eslint, go vet) | DIF | Style and pattern enforcement |
| AGENTS.md coding standards | File | Language-specific rules |

**How it works**: Agent implements a change -> check-decisions.sh validates against architectural boundaries (e.g., no cross-layer imports, no new dependencies without justification) -> if violation detected, agent gets structured feedback about what rule was broken and why.

### Quality Layer

| Component | Type | Purpose |
|-----------|------|---------|
| `scripts/agent/lint-fast.sh` | DIF | Quick syntax/style check (<5 seconds) |
| `scripts/agent/verify.sh` | DIF | Full build + test for affected services |
| `scripts/agent/quality-gate.sh` | DIF | Orchestrates: lint-fast -> verify -> report |

**How it works**: Agent writes code -> runs lint-fast.sh for immediate feedback -> fixes issues -> runs quality-gate.sh for full verification -> only declares "done" when quality-gate exits 0.

### Continuity Layer

| Component | Type | Purpose |
|-----------|------|---------|
| `scripts/agent/save-progress.sh` | DIF | Snapshot current state to progress file |
| `scripts/agent/load-progress.sh` | DIF | Bootstrap session from saved state |
| `docs/agent/continuity-protocol.md` | File | Convention for progress format and session startup |

**How it works**: At end of session -> save-progress.sh captures: current task, completed steps, remaining work, relevant files, blockers. At start of next session -> load-progress.sh outputs saved state -> agent continues without human re-explanation.

### Meta-cognition Layer

| Component | Type | Purpose |
|-----------|------|---------|
| `scripts/agent/meta-check.sh` | DIF | Detect iterations, time elapsed, repetition patterns |
| `docs/agent/meta-cognition-protocol.md` | File | When to escalate, delegate, or change strategy |

**How it works**: Periodically during execution -> meta-check.sh analyzes: how many iterations on current approach? how long since last progress? is the same tool being called repeatedly? -> if thresholds exceeded, outputs recommendation (try different approach, delegate to sub-agent, ask human).

---

## 2. Layer Implementations for Physical AI Pipelines (Future)

### Context Layer

| Component | Type | Purpose |
|-----------|------|---------|
| MCP tools with rich responses | Code | Agent queries return context, not just data |
| Pipeline templates | File | Curated SDG -> train -> eval patterns as YAML |
| Domain knowledge in tool docstrings | Code | Tool descriptions teach Physical AI semantics |

### Decision Layer

| Component | Type | Purpose |
|-----------|------|---------|
| Safety guardrails | Code | Cost caps, resource limits, dangerous operation blocks |
| Topology constraints | Code | GPU placement rules per workload type |
| Resource validation | Code | Prevent impossible resource requests |

### Quality Layer

| Component | Type | Purpose |
|-----------|------|---------|
| Pipeline validation | Code | Verify stage outputs before next stage |
| Sim-to-real metrics | Code | Confidence scoring for transfer quality |
| Checkpoint verification | Code | Validate checkpoint integrity before resume |

### Continuity Layer

| Component | Type | Purpose |
|-----------|------|---------|
| Multi-hour pipeline state | Code | Track 9+ hour training runs across sessions |
| Checkpoint/resume | Code | Resume from last good checkpoint on failure |
| Cross-stage handoff | Code | Pass state between SDG, training, eval stages |

### Meta-cognition Layer

| Component | Type | Purpose |
|-----------|------|---------|
| Pipeline divergence detection | Code | Training not converging, resource waste |
| Strategy adaptation | Code | Switch GPU pools, adjust batch size, change approach |
| Resource optimization | Code | Historical data for better resource estimates |

### MCP Server Design

The same 8-10 tools from the original substrate design, now framed as Physical AI pipeline layer implementations:

```
osmo_submit_workflow(spec_yaml, pool, priority?)
  -> {workflow_id, estimated_duration, estimated_cost, monitoring_url}
  Context: validates spec against Physical AI patterns
  Decision: warns on topology issues, estimates cost before submit
  Quality: returns monitoring URL for verification

osmo_query_workflow(name_or_id)
  -> {status, tasks[], phase, metrics, logs_url, next_actions[]}
  Context: includes suggested next actions based on state
  Continuity: full workflow state for session bootstrap

osmo_get_logs(workflow, task?, lines?, search?)
  -> {log_text, error_summary?, suggested_diagnosis?}
  Quality: recognizes common Physical AI failure patterns
  Meta-cognition: suggests when to try different approach

osmo_cancel_workflow(name_or_id, reason)
  -> {success, resources_freed}
  Decision: requires reason for audit trail

osmo_check_resources(pool?, gpu_type?, gpu_count?)
  -> {pools[], recommendations, queue_estimates}
  Context: understands workload types, suggests optimal pools
  Decision: warns if requested resources exceed quotas

osmo_list_datasets(bucket?, prefix?, tag?)
  -> {datasets[], storage_stats}
  Context: dataset metadata for pipeline reasoning

osmo_get_cluster_health(cluster?)
  -> {nodes[], failing_gpus[], recent_events[], risk_assessment}
  Meta-cognition: identifies degradation patterns

osmo_diagnose_failure(workflow_id)
  -> {failure_type, root_cause, evidence, remediation_steps[]}
  Quality: OSMO-specific failure taxonomy
  Meta-cognition: suggests whether to retry or change approach
```

Optional expansion (Phase 2):
```
osmo_recommend_topology(gpu_count, workload_type)
osmo_estimate_cost(spec_yaml, pool?)
```

---

## 3. Hybrid Architecture: MCP + Event Hooks

### Why Both

- **MCP** (pull): Agent asks "what's the cluster health?" Useful for agent-initiated queries.
- **Event hooks** (push): OSMO tells agent "cluster health just changed." Useful for events the agent needs to know about but didn't ask for.

### Event Hook Triggers

| Event | Trigger | Agent Action |
|-------|---------|--------------|
| Cluster health degraded | GPU ECC errors exceed threshold | Consider workload migration |
| Training run failed | Non-zero exit code | Diagnose failure, decide retry vs. investigate |
| Resource availability changed | Pool freed up GPUs | Check if queued workloads can now be submitted |
| Checkpoint completed | Periodic checkpoint saved | Update progress tracking |
| Cost threshold exceeded | GPU-hours past budget | Alert, consider early stopping |

### Implementation

MCP server handles both:
- **Standard MCP tools**: Agent calls when it needs information
- **Event notifications**: OSMO pushes via MCP sampling or out-of-band webhook
- Both share the same authentication and authorization model

---

## 4. Safety Guardrails

| Guardrail | Implementation | Layer |
|-----------|---------------|-------|
| JWT auth via environment variable | NOT in tool arguments or context window | Decision |
| Destructive tools require confirmation | `cancel` needs explicit `reason` parameter | Decision |
| Read-only by default | Only submit/cancel modify state | Decision |
| Tool invocation counter | Configurable max (default 100/session), alert at 80% | Meta-cognition |
| Dead-man switch | Alert if agent runs >30 min without verification | Meta-cognition |
| Cost estimator | Show estimated GPU-hours before submission | Decision |
| Loop detection | Same tool call 3x with same args = stop | Meta-cognition |

---

## 5. Flywheel as Community Asset

### Three Data Layers (All Fully Open)

| Layer | Data | Timeline | Value Without It |
|-------|------|----------|-----------------|
| **Execution telemetry** | GPU utilization, failure rates, scheduling decisions | Immediate | N/A (auto-generated) |
| **Agent interactions** | Tool call sequences, success/failure patterns | Weeks | Phase 1 tools work without it |
| **Pipeline intelligence** | Config -> outcome correlations, optimal parameters | 12-18 months | Phase 1 uses hard-coded domain knowledge |

### Cold-Start Reality

Phase 1 tools must be valuable WITHOUT pipeline intelligence data:

- `osmo_diagnose_failure`: Uses hard-coded failure taxonomy (GPU, NCCL, OOM, checkpoint, data, scheduling)
- `osmo_check_resources`: Uses current availability, not historical patterns
- `osmo_submit_workflow`: Validates spec structure, not historical success rates

As telemetry accumulates, tools get smarter. But they must be useful on day 1.

### Ecosystem Gravity Model

```
More teams use OSMO
  -> More GPU-hours orchestrated (NVIDIA revenue)
  -> More pipeline telemetry generated (all open)
  -> Better tool recommendations (community benefit)
  -> More teams adopt OSMO
  -> (cycle continues)
```

This is the K8s/Linux model. The project is fully open. NVIDIA benefits from deepest integration with own hardware/software stack. Community benefits from accumulated intelligence. No lock-in, maximum adoption velocity.

---

## 6. E2E POC: Autonomous Agent Orchestrator

The POC proves the framework end-to-end on a real task: migrating OSMO from Pydantic v1 (1.10.26) to v2 (2.12.5) across 68 files, 212 BaseModel subclasses, 657 usages.

### System Architecture

```
┌─────────────┐         ┌──────────────────────┐
│   Human     │         │   Object Storage     │
│  (Web UI)   │◄───────►│   (S3 bucket)        │
│  static SPA │  read/  │                      │
└─────────────┘  write  │  /tasks/             │
                        │  /questions/          │
                        │  /subtasks/           │
                        │  /progress/           │
                        │  /interventions/      │
                        │  /artifacts/          │
                        └──────────┬───────────┘
                                   │ read/write
                        ┌──────────▼───────────┐
                        │  Agent Orchestrator   │
                        │  (ephemeral compute)  │
                        │  ┌─ Coordinator ────┐ │
                        │  │ DIF scripts      │ │
                        │  └───────┬──────────┘ │
                        │  ┌───────▼──────────┐ │
                        │  │ Sub-agents (LLM)  │ │
                        │  └──────────────────┘ │
                        └───────────────────────┘
```

Three components:
1. **Object storage** -- Single source of truth. Everything survives ephemeral sessions.
2. **Agent orchestrator** -- Runs in ephemeral compute. Reads state on startup, does work, writes state back. Can die and resume.
3. **Static web UI** -- S3-hosted SPA. Reads state, renders questions, writes answers. No backend server.

### Orchestrator Implementation

The orchestrator is the product. It takes any high-level task and drives it autonomously.

**Core loop**: Load state → incorporate answers → pick next unblocked subtask → execute via sub-agent → quality gate → save progress → repeat until done or fully blocked.

**Key behaviors**:
- Stateless sessions: bootstraps entirely from object storage
- Parallel unblocking: if subtask 13 is blocked but 14-38 can proceed, keep going
- Bounded retries: 2 self-correction attempts, then escalate to human
- Exit is normal: designed to exit when blocked, resume on next session
- Cron/supervisor keeps spawning sessions; answer webhook triggers immediate resumption

**Runtime**: Claude Code first, agent-agnostic interface. Core logic in DIF scripts, thin Claude Code adapter.

### Object Storage Schema

Strict envelope (DIF-parseable: `id`, `status`, `timestamps`, `phase`) + fluid content (LLM-generated: `context`, `reasoning`, `question`).

```
s3://osmo-agent/{task-id}/
├── task.json              # Original prompt + decomposed plan
├── state.json             # Current phase, completed/blocked subtasks, session count
├── questions/
│   └── q-NNN.json         # Context + options + answer + impact
├── subtasks/
│   └── st-NNN.json        # Per-subtask state + quality gate results
├── interventions.json     # Every human interaction, categorized, avoidability tagged
└── artifacts/
    ├── st-NNN.patch       # Code changes per subtask
    └── framework-improvements/  # Generated patches to DIF/knowledge docs
```

### Static Web UI

Single HTML file on S3. No framework, no build step.

- Polls `state.json` on interval (30s)
- Renders pending questions with clickable options + free-text fallback
- Writes answers back via presigned URL or tiny Lambda
- Shows: task progress bar, recent activity log, intervention count
- Auth: presigned URLs with short TTL or API Gateway + Lambda with basic auth

### Pydantic Migration: Task-Specific Execution

**Discovery phase (DIF)**:
- Scan `requirements.txt` → `pydantic==1.10.26`
- Grep for Pydantic imports → group by module dependency order
- Detect v1 patterns: `Config` inner class, `.dict()`, `.json()`, `Field(...)`, `Optional` vs `| None`
- Output: `task.json` with subtask list and dependency graph

**Planning phase (LLM)**:
- Read Pydantic v2 migration guide + architecture-intent.md
- Order: leaf modules first, shared libs last (tests stay green incrementally)
- Flag high-risk areas (postgres connector: 85 usages, workflow objects: 49)

**Execution phase (per subtask, sub-agent)**:
- Each sub-agent gets scoped context: target files + migration knowledge doc + learned decisions
- Apply v1→v2 transformations → lint-fast → module tests → green? patch + done : self-correct or question

**Validation phase (DIF)**:
- Full quality-gate across entire codebase
- Verify no v1 patterns remain
- Final report

**What makes this a framework proof**: The orchestrator doesn't know it's doing a Pydantic migration. It executes a generic task→plan→execute→validate loop. The Pydantic-specific knowledge lives in a knowledge doc. Swap the knowledge doc for "add OpenTelemetry tracing" and the same orchestrator runs.

### Intervention Feedback Loop

After task completion:
1. Read `interventions.json`
2. Group avoidable interventions by `framework_fix.type`
3. Generate concrete patches to framework files (knowledge docs, DIF scripts, AGENTS.md)
4. Write patches to `artifacts/framework-improvements/`
5. These become a PR -- the framework improves itself from the experience

**Target metric**: ≤2 human interventions for the entire Pydantic migration.
