# E2E POC: OSMO-Native Autonomous Agent Orchestrator — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build an OSMO-native agent orchestrator that runs as an OSMO workflow, submits child workflows for each migration module, uses git as state passing, and tracks human interventions. First task: Pydantic v1→v2 migration.

**Architecture:** Orchestrator = OSMO workflow task (Claude Code + OSMO CLI + git). Child workflows = one per module (Claude Code + git). Git branch = code state. S3 = human interaction only.

**Tech Stack:** OSMO workflows (YAML), bash (DIF scripts), Claude Code CLI, git, S3 (questions only), vanilla HTML/JS (web UI)

**Spec:** `docs/superpowers/specs/2026-03-19-e2e-poc-autonomous-orchestrator-design.md`

---

## File Structure

### New Files

```
scripts/agent/orchestrator/
├── orchestrator.yaml            # OSMO workflow: the orchestrator task
├── child-workflow-template.yaml # OSMO workflow template: one migration subtask
├── orchestrator.sh              # Main loop: discovery → plan → submit children → validate
├── discovery.sh                 # DIF: scan codebase, output module list as JSON
├── planner.sh                   # DIF: order modules by dependency, output subtask plan
├── submit-child.sh              # DIF: generate child YAML from template, submit via osmo CLI
├── poll-workflow.sh             # DIF: poll child workflow status until done/failed
├── check-answer.sh             # DIF: check S3 for human answers, incorporate
├── write-question.sh            # DIF: write structured question JSON to S3
├── intervention.sh              # DIF: log intervention, generate framework patches
├── child-prompt.md              # Claude Code prompt template for child migrations

docs/agent/pydantic-v2-migration.md  # Task knowledge doc

web/
└── index.html                   # Static SPA: progress, questions, answers
```

### Modified Files

```
scripts/agent/verify.sh          # Fix Python path globs to cover subdirectories
```

---

## Task 1: OSMO Orchestrator Workflow YAML

The workflow spec that runs the orchestrator as an OSMO task.

**Files:**
- Create: `scripts/agent/orchestrator/orchestrator.yaml`

- [ ] **Step 1: Create the orchestrator workflow YAML**

```yaml
# scripts/agent/orchestrator/orchestrator.yaml
workflow:
  name: agent-orchestrator
  resources:
    default:
      cpu: 4
      memory: 8Gi
      storage: 50Gi
  tasks:
  - name: orchestrator
    image: {{orchestrator_image}}
    command: ["bash"]
    args: ["/tmp/orchestrator.sh"]
    credentials:
      github-pat: /tmp/github
    environment:
      GITHUB_REPO: "{{github_repo}}"
      BRANCH_NAME: "{{branch_name}}"
      S3_BUCKET: "{{s3_bucket}}"
      TASK_ID: "{{task_id}}"
      TASK_PROMPT: "{{task_prompt}}"
      KNOWLEDGE_DOC: "{{knowledge_doc}}"
    files:
    - path: /tmp/setup_git.sh
      contents: |-
        set -e
        GITHUB_PAT=$(cat /tmp/github/github-pat)
        git config --global credential.helper store
        echo "https://token:${GITHUB_PAT}@github.com" > ~/.git-credentials
        git config --global user.email "osmo-agent@nvidia.com"
        git config --global user.name "OSMO Agent"

    - path: /tmp/orchestrator.sh
      contents: |-
        set -euo pipefail

        # Setup git auth
        bash /tmp/setup_git.sh

        # Clone repo and create migration branch
        cd /workspace
        git clone "$GITHUB_REPO" repo
        cd repo

        # Check if branch exists, create if not
        if git ls-remote --heads origin "$BRANCH_NAME" | grep -q "$BRANCH_NAME"; then
          git checkout "$BRANCH_NAME"
          git pull origin "$BRANCH_NAME"
        else
          git checkout -b "$BRANCH_NAME"
          git push -u origin "$BRANCH_NAME"
        fi

        # Run the orchestrator loop
        bash scripts/agent/orchestrator/orchestrator.sh

default-values:
  orchestrator_image: ubuntu:24.04
  github_repo: https://github.com/NVIDIA/osmo.git
  branch_name: agent/pydantic-v2-migration
  s3_bucket: osmo-agent
  task_id: pydantic-v2
  task_prompt: "Migrate from Pydantic v1 to v2.12.5, no regressions, full advantage of v2"
  knowledge_doc: docs/agent/pydantic-v2-migration.md
```

- [ ] **Step 2: Verify YAML is valid**

Run: `python3 -c "import yaml; yaml.safe_load(open('scripts/agent/orchestrator/orchestrator.yaml'))" && echo "Valid YAML"`
Expected: `Valid YAML`

- [ ] **Step 3: Commit**

```bash
git add scripts/agent/orchestrator/orchestrator.yaml
git commit -m "feat(orchestrator): add OSMO orchestrator workflow YAML"
```

---

## Task 2: Child Workflow Template

The YAML template that the orchestrator instantiates for each module migration.

**Files:**
- Create: `scripts/agent/orchestrator/child-workflow-template.yaml`
- Create: `scripts/agent/orchestrator/child-prompt.md`

- [ ] **Step 1: Create the child workflow template**

```yaml
# scripts/agent/orchestrator/child-workflow-template.yaml
# Template variables: MODULE, FILES, DESCRIPTION, GITHUB_REPO, BRANCH_NAME, KNOWLEDGE_DOC
workflow:
  name: migrate-MODULE_PLACEHOLDER
  resources:
    default:
      cpu: 4
      memory: 8Gi
      storage: 50Gi
  tasks:
  - name: migrate
    image: ORCHESTRATOR_IMAGE_PLACEHOLDER
    command: ["bash"]
    args: ["/tmp/migrate.sh"]
    credentials:
      github-pat: /tmp/github
    files:
    - path: /tmp/setup_git.sh
      contents: |-
        set -e
        GITHUB_PAT=$(cat /tmp/github/github-pat)
        git config --global credential.helper store
        echo "https://token:${GITHUB_PAT}@github.com" > ~/.git-credentials
        git config --global user.email "osmo-agent@nvidia.com"
        git config --global user.name "OSMO Agent"

    - path: /tmp/migrate.sh
      contents: |-
        set -euo pipefail
        bash /tmp/setup_git.sh

        cd /workspace
        git clone GITHUB_REPO_PLACEHOLDER repo
        cd repo
        git checkout BRANCH_PLACEHOLDER
        git pull origin BRANCH_PLACEHOLDER

        # Run Claude Code with scoped prompt
        claude --print --dangerously-skip-permissions -p "$(cat /tmp/prompt.md)"

        # Stage, commit, push
        git add -A
        if git diff --cached --quiet; then
          echo "No changes to commit"
        else
          git commit -m "migrate(pydantic): MODULE_PLACEHOLDER — DESCRIPTION_PLACEHOLDER"
          git push origin BRANCH_PLACEHOLDER
        fi

    - path: /tmp/prompt.md
      contents: |-
        PROMPT_PLACEHOLDER
```

Note: Placeholders (MODULE_PLACEHOLDER, etc.) are replaced by `submit-child.sh` using sed before submission.

- [ ] **Step 2: Create the child prompt template**

```markdown
# scripts/agent/orchestrator/child-prompt.md
You are migrating Pydantic v1 to v2.12.5 for the module: {{MODULE}}

## Files to migrate
{{FILES_LIST}}

## Task
{{DESCRIPTION}}

## Migration Guide
Read `{{KNOWLEDGE_DOC}}` in this repo for the full migration patterns.

{{LEARNED_DECISIONS}}

## Instructions
1. Read each file listed above
2. Apply Pydantic v1 → v2 transformations per the migration guide
3. Key changes: `.dict()` → `.model_dump()`, `class Config:` → `model_config = ConfigDict(...)`, `Optional[X]` → `X | None = None`
4. Run `scripts/agent/lint-fast.sh` to verify no syntax errors
5. Do NOT change field names, field types, or wire format — only Pydantic API surface
6. If a model's output is used in Redis, PostgreSQL, or API responses, verify format is unchanged
```

- [ ] **Step 3: Commit**

```bash
git add scripts/agent/orchestrator/child-workflow-template.yaml scripts/agent/orchestrator/child-prompt.md
git commit -m "feat(orchestrator): add child workflow template and prompt"
```

---

## Task 3: Discovery DIF Script

Scan the codebase for Pydantic usage and output structured JSON.

**Files:**
- Create: `scripts/agent/orchestrator/discovery.sh`

- [ ] **Step 1: Write the discovery script**

Create `scripts/agent/orchestrator/discovery.sh` — a bash script that:
- Finds all Python files importing pydantic under `src/`
- Groups by module (first two path components, e.g., `lib/utils`, `service/core`)
- Counts: BaseModel subclasses, `.dict()` calls, `class Config:` inner classes per module
- Outputs JSON to stdout: `{"pydantic_version": "...", "modules": [...], "summary": {...}}`

The script should work when run from the repo root: `bash scripts/agent/orchestrator/discovery.sh`

Use associative arrays in bash to group by module. Output valid JSON (verify with `python3 -c "import json,sys; json.load(sys.stdin)"`).

- [ ] **Step 2: Test the script**

Run: `bash scripts/agent/orchestrator/discovery.sh | python3 -c "import json,sys; d=json.load(sys.stdin); print(f'Found {len(d[\"modules\"])} modules, {d[\"summary\"][\"total_files\"]} files')"`
Expected: Something like `Found 15 modules, 68 files`

- [ ] **Step 3: Commit**

```bash
git add scripts/agent/orchestrator/discovery.sh
git commit -m "feat(orchestrator): add Pydantic discovery DIF script"
```

---

## Task 4: Planner DIF Script

Order modules by dependency (libs first, consumers last).

**Files:**
- Create: `scripts/agent/orchestrator/planner.sh`

- [ ] **Step 1: Write the planner script**

Create `scripts/agent/orchestrator/planner.sh` — takes discovery JSON from stdin, outputs ordered subtask list as JSON.

Ordering rules (DIF — no LLM needed):
1. `lib/data/*` — lowest level, migrate first
2. `lib/utils`, `lib/rsync` — shared libraries
3. `utils/*` — utility modules
4. `operator/*` — operator code
5. `service/worker`, `service/agent`, `service/logger`, `service/router`, `service/delayed*` — services
6. `service/core` — core service (highest dependency, migrate last)
7. `cli/*` — CLI (depends on lib/utils)
8. `tests/*` — test helpers

Output JSON: `{"subtasks": [{"id": "st-001", "module": "lib/data", "files": [...], "description": "..."}], "dependency_graph": {"st-005": ["st-001", "st-002"]}}`

- [ ] **Step 2: Test the planner**

Run: `bash scripts/agent/orchestrator/discovery.sh | bash scripts/agent/orchestrator/planner.sh | python3 -c "import json,sys; d=json.load(sys.stdin); print(f'{len(d[\"subtasks\"])} subtasks planned')"`
Expected: Something like `15 subtasks planned`

- [ ] **Step 3: Commit**

```bash
git add scripts/agent/orchestrator/planner.sh
git commit -m "feat(orchestrator): add module ordering planner DIF script"
```

---

## Task 5: Submit-Child and Poll Scripts

Generate child workflow YAML from template and submit to OSMO.

**Files:**
- Create: `scripts/agent/orchestrator/submit-child.sh`
- Create: `scripts/agent/orchestrator/poll-workflow.sh`

- [ ] **Step 1: Write submit-child.sh**

Create `scripts/agent/orchestrator/submit-child.sh` — takes module info as args, generates workflow YAML from template, submits via `osmo workflow submit`.

Usage: `submit-child.sh <module> <files_csv> <description>`

The script:
1. Reads `child-workflow-template.yaml`
2. Replaces placeholders with actual values using sed
3. Builds the Claude Code prompt from `child-prompt.md` template
4. Writes the generated YAML to a temp file
5. Runs `osmo workflow submit <temp>.yaml`
6. Outputs the workflow ID

- [ ] **Step 2: Write poll-workflow.sh**

Create `scripts/agent/orchestrator/poll-workflow.sh` — polls workflow status until complete or failed.

Usage: `poll-workflow.sh <workflow-id> [poll-interval-seconds]`

The script:
1. Runs `osmo workflow query <id>` in a loop
2. Parses status from output
3. Exits 0 on COMPLETED, exits 1 on FAILED_*
4. Default poll interval: 30 seconds

- [ ] **Step 3: Commit**

```bash
git add scripts/agent/orchestrator/submit-child.sh scripts/agent/orchestrator/poll-workflow.sh
git commit -m "feat(orchestrator): add child workflow submission and polling scripts"
```

---

## Task 6: Question and Intervention Scripts

S3 interaction for async human communication.

**Files:**
- Create: `scripts/agent/orchestrator/write-question.sh`
- Create: `scripts/agent/orchestrator/check-answer.sh`
- Create: `scripts/agent/orchestrator/intervention.sh`

- [ ] **Step 1: Write write-question.sh**

Usage: `write-question.sh <question-id> <subtask-id> <context> <question-text> <options-json>`

Writes a question JSON file to `s3://$S3_BUCKET/$TASK_ID/questions/q-NNN.json` with strict envelope (id, status, timestamps) and fluid content (context, question, options).

- [ ] **Step 2: Write check-answer.sh**

Usage: `check-answer.sh`

Lists all question files in S3, checks for `"status": "answered"` on any pending question. Outputs the answered question IDs and their answers. Returns exit code 0 if answers found, 1 if none.

- [ ] **Step 3: Write intervention.sh**

Usage: `intervention.sh <question-id> <category> <avoidable> <framework-fix-json>`

Appends an intervention record to `s3://$S3_BUCKET/$TASK_ID/interventions.json`. After all interventions, generates framework improvement suggestions.

- [ ] **Step 4: Commit**

```bash
git add scripts/agent/orchestrator/write-question.sh scripts/agent/orchestrator/check-answer.sh scripts/agent/orchestrator/intervention.sh
git commit -m "feat(orchestrator): add S3 question/answer and intervention scripts"
```

---

## Task 7: Main Orchestrator Loop

The core script that ties everything together.

**Files:**
- Create: `scripts/agent/orchestrator/orchestrator.sh`

- [ ] **Step 1: Write the main orchestrator loop**

Create `scripts/agent/orchestrator/orchestrator.sh` — the core loop. Run from inside the orchestrator OSMO task.

```
#!/usr/bin/env bash
# Main orchestrator loop.
# Expects: GITHUB_REPO, BRANCH_NAME, S3_BUCKET, TASK_ID, KNOWLEDGE_DOC env vars
# Expects: CWD is the repo root with the migration branch checked out

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Phase 1: Discovery
echo "=== Phase 1: Discovery ==="
DISCOVERY=$("$SCRIPT_DIR/discovery.sh")
echo "$DISCOVERY" | python3 -c "import json,sys; d=json.load(sys.stdin); print(f'Found {d[\"summary\"][\"total_files\"]} files in {len(d[\"modules\"])} modules')"

# Phase 2: Planning
echo "=== Phase 2: Planning ==="
PLAN=$(echo "$DISCOVERY" | "$SCRIPT_DIR/planner.sh")
SUBTASK_COUNT=$(echo "$PLAN" | python3 -c "import json,sys; print(len(json.load(sys.stdin)['subtasks']))")
echo "Planned $SUBTASK_COUNT subtasks"

# Phase 3: Execution
echo "=== Phase 3: Execution ==="
COMPLETED=0
FAILED=0
BLOCKED=0
QUESTION_COUNTER=0

echo "$PLAN" | python3 -c "
import json, sys
plan = json.load(sys.stdin)
for st in plan['subtasks']:
    print(f\"{st['id']}|{st['module']}|{','.join(st['files'])}|{st['description']}\")
" | while IFS='|' read -r ST_ID MODULE FILES DESCRIPTION; do

  echo "--- Subtask $ST_ID: $MODULE ---"

  # Check for pending human answers before each subtask
  if "$SCRIPT_DIR/check-answer.sh" 2>/dev/null; then
    echo "  Human answer received, incorporating..."
    # TODO: incorporate answer logic
  fi

  # Submit child workflow
  WF_ID=$("$SCRIPT_DIR/submit-child.sh" "$MODULE" "$FILES" "$DESCRIPTION")
  echo "  Submitted workflow: $WF_ID"

  # Poll until done
  if "$SCRIPT_DIR/poll-workflow.sh" "$WF_ID"; then
    echo "  Child workflow completed"

    # Pull changes
    git pull origin "$BRANCH_NAME"

    # Run quality gate
    if bash scripts/agent/lint-fast.sh 2>/dev/null; then
      echo "  Quality gate passed"
      COMPLETED=$((COMPLETED + 1))
    else
      echo "  Quality gate FAILED — reverting"
      git revert --no-edit HEAD
      git push origin "$BRANCH_NAME"
      QUESTION_COUNTER=$((QUESTION_COUNTER + 1))
      "$SCRIPT_DIR/write-question.sh" "q-$QUESTION_COUNTER" "$ST_ID" \
        "Module $MODULE failed quality gate after migration" \
        "How should I proceed?" \
        '[{"key":"A","label":"Skip this module"},{"key":"B","label":"Provide guidance"}]'
      BLOCKED=$((BLOCKED + 1))
    fi
  else
    echo "  Child workflow FAILED"
    QUESTION_COUNTER=$((QUESTION_COUNTER + 1))
    "$SCRIPT_DIR/write-question.sh" "q-$QUESTION_COUNTER" "$ST_ID" \
      "Child workflow for $MODULE failed" \
      "How should I proceed?" \
      '[{"key":"A","label":"Skip"},{"key":"B","label":"Retry with guidance"}]'
    BLOCKED=$((BLOCKED + 1))
  fi
done

# Phase 4: Validation
echo "=== Phase 4: Final Validation ==="
bash scripts/agent/quality-gate.sh || echo "Final validation had issues"

# Summary
echo "=== Summary ==="
echo "Completed: $COMPLETED / $SUBTASK_COUNT"
echo "Blocked: $BLOCKED"
echo "Questions: $QUESTION_COUNTER"
```

This is the skeleton — the actual script will need refinement, but this captures the full loop.

- [ ] **Step 2: Verify the script is syntactically valid**

Run: `bash -n scripts/agent/orchestrator/orchestrator.sh && echo "Syntax OK"`
Expected: `Syntax OK`

- [ ] **Step 3: Commit**

```bash
git add scripts/agent/orchestrator/orchestrator.sh
git commit -m "feat(orchestrator): add main orchestrator loop script"
```

---

## Task 8: Pydantic Migration Knowledge Doc

The pluggable knowledge doc that makes this a Pydantic migration.

**Files:**
- Create: `docs/agent/pydantic-v2-migration.md`

- [ ] **Step 1: Write the knowledge doc**

Create `docs/agent/pydantic-v2-migration.md` with:
- V1 → V2 transformation patterns (imports, Config→ConfigDict, .dict()→.model_dump(), .json()→.model_dump_json(), parse_obj→model_validate, Optional field changes, Field parameter renames)
- OSMO-specific notes: high-risk modules, wire compatibility rules, rules about not changing field names/types

See the plan from the previous iteration for the full content.

- [ ] **Step 2: Commit**

```bash
git add docs/agent/pydantic-v2-migration.md
git commit -m "docs: add Pydantic v2 migration knowledge doc for orchestrator"
```

---

## Task 9: Static Web UI

Single HTML file for async human interaction.

**Files:**
- Create: `web/index.html`

- [ ] **Step 1: Create the static SPA**

Create `web/index.html` — single HTML file with embedded CSS and JS:
- Takes config via URL params: `?api=<s3-base-url>&task=<task-id>`
- Polls S3 for `state.json` (or derives state from questions/) every 30s
- Renders pending questions with clickable options + free-text
- On submit: writes answer via presigned PUT URL
- Shows progress (derived from git log or question count)
- Shows intervention summary
- No framework, no dependencies, no build step

- [ ] **Step 2: Commit**

```bash
git add web/index.html
git commit -m "feat: add static web UI for async human interaction"
```

---

## Task 10: Fix verify.sh Path Coverage

**Files:**
- Modify: `scripts/agent/verify.sh`

- [ ] **Step 1: Read verify.sh and identify non-recursive Python globs**

Look for patterns like `src/utils/*.py` that miss subdirectories like `src/utils/job/*.py`.

- [ ] **Step 2: Fix globs to be recursive**

Change non-recursive patterns to recursive (e.g., `src/utils/**/*.py` or use `find`).

- [ ] **Step 3: Run quality gate to verify**

Run: `bash scripts/agent/quality-gate.sh`
Expected: Passes

- [ ] **Step 4: Commit**

```bash
git add scripts/agent/verify.sh
git commit -m "fix: make verify.sh Python path detection recursive"
```

---

## Task 11: Integration Test — Dry Run

Test the full orchestrator pipeline without actually submitting OSMO workflows.

**Files:**
- Create: `scripts/agent/orchestrator/test-dry-run.sh`

- [ ] **Step 1: Write dry-run test**

Create `scripts/agent/orchestrator/test-dry-run.sh` — tests the orchestrator pipeline with mocked `osmo` CLI:

1. Create a mock `osmo` command that echoes workflow IDs and returns success
2. Run `discovery.sh` → verify valid JSON output
3. Pipe to `planner.sh` → verify ordered subtasks
4. Run `submit-child.sh` with mock osmo → verify YAML generation
5. Run `write-question.sh` → verify question JSON structure
6. Verify all scripts exit cleanly

- [ ] **Step 2: Run the dry-run test**

Run: `bash scripts/agent/orchestrator/test-dry-run.sh`
Expected: All checks pass

- [ ] **Step 3: Commit**

```bash
git add scripts/agent/orchestrator/test-dry-run.sh
git commit -m "test(orchestrator): add dry-run integration test"
```

---

## Summary

| Task | Component | Type | Files |
|------|-----------|------|-------|
| 1 | Orchestrator YAML | OSMO workflow | `orchestrator.yaml` |
| 2 | Child Template | OSMO workflow + prompt | `child-workflow-template.yaml`, `child-prompt.md` |
| 3 | Discovery | DIF (bash) | `discovery.sh` |
| 4 | Planner | DIF (bash) | `planner.sh` |
| 5 | Submit + Poll | DIF (bash) | `submit-child.sh`, `poll-workflow.sh` |
| 6 | Questions + Interventions | DIF (bash + S3) | `write-question.sh`, `check-answer.sh`, `intervention.sh` |
| 7 | Orchestrator Loop | DIF (bash) | `orchestrator.sh` |
| 8 | Knowledge Doc | Markdown | `pydantic-v2-migration.md` |
| 9 | Web UI | Static HTML | `index.html` |
| 10 | verify.sh Fix | Bash | `verify.sh` |
| 11 | Dry-Run Test | Bash | `test-dry-run.sh` |

**Total: 11 tasks, 14 files, 11 commits**

**What's eliminated vs. old plan**: `storage.py`, `lock.py`, `coordinator.py`, `executor.py`, `run.py`, `models.py`, `config.py`, and all Python tests. Replaced by bash scripts + OSMO workflow YAMLs. ~70% less code.

After all tasks complete, the orchestrator runs with:
```bash
osmo workflow submit scripts/agent/orchestrator/orchestrator.yaml \
  --set github_repo=https://github.com/NVIDIA/osmo.git \
  --set branch_name=agent/pydantic-v2-migration \
  --set s3_bucket=osmo-agent
```
