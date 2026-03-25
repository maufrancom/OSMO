<!--
SPDX-FileCopyrightText: Copyright (c) 2025 NVIDIA CORPORATION & AFFILIATES. All rights reserved.
SPDX-License-Identifier: Apache-2.0
-->

# Skill: Memory

Write memories so future agents (and future sessions of yourself) learn from your experience.

## What to Remember

### Episodic (this session)

Write one episode file per session. Captures what happened — the narrative.

- What you attempted and what worked
- What failed and why
- Errors encountered (exact error messages)
- Approaches tried and abandoned
- How long things took
- What surprised you about this codebase

### Long-term (across sessions)

Append to shared knowledge files. Captures patterns — the lessons.

- Repo-specific pitfalls (e.g., circular imports, hidden dependencies)
- Effective commands (e.g., fast test targets, useful flags)
- Transformation patterns that apply to recurring work
- Dependencies between modules that aren't obvious from imports
- Things the knowledge doc or discovery didn't cover

## Where to Write

```
.agent/memory/
├── episodes/
│   ├── session-<timestamp>.json     ← one per session (you write yours)
│   └── st-005-<timestamp>.json      ← child agents write theirs
└── long-term.json                    ← accumulated patterns (append-only)
```

### Episode format

```json
{
  "session": "2026-03-24T14:30:00Z",
  "agent": "root",
  "subtask": null,
  "duration_minutes": 12,
  "outcome": "completed",
  "summary": "Completed task X across N files",
  "actions": [
    "Read repo instructions and relevant documentation",
    "Ran automated tooling as baseline",
    "Manually fixed remaining issues"
  ],
  "errors": [
    {"file": "path/to/file.py", "error": "description of error", "fix": "what resolved it"}
  ],
  "learned": [
    "Non-obvious finding about the codebase",
    "Effective approach that should be reused",
    "Pitfall to avoid in future sessions"
  ]
}
```

### Long-term format

```json
{
  "patterns": [
    {"category": "architecture", "lesson": "Description of a structural pattern or pitfall", "source": "session-<timestamp>"},
    {"category": "tooling", "lesson": "Effective command or tool usage discovered", "source": "session-<timestamp>"}
  ]
}
```

## When to Write

**During execution** — after key events:
- After completing a subtask: write what worked
- After hitting an error: write the error and how you resolved it
- After discovering something non-obvious: write it immediately (don't wait for end of session)

**On session end — always.** Whether you succeeded, failed, or got interrupted:
- Write your episode file
- Append any new patterns to long-term.json
- Commit and push

```bash
mkdir -p .agent/memory/episodes
# Write episode
cat > .agent/memory/episodes/session-$(date -u +%Y%m%dT%H%M%SZ).json << 'EOF'
{ ... your episode ... }
EOF
# Append to long-term (read existing, merge, write back)
# Commit
git add .agent/memory/
git commit -m "$COMMIT_PREFIX: session memory"
git push origin "$BRANCH_NAME"
```

## Reading Memory (on startup)

Before planning, check if prior sessions left memories:

```bash
# Quick check
ls .agent/memory/episodes/ 2>/dev/null
cat .agent/memory/long-term.json 2>/dev/null
```

Long-term patterns are especially valuable — they capture lessons that won't be in the knowledge doc or discovered artifacts. Read them before starting work.
