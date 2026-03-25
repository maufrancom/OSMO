<!--
SPDX-FileCopyrightText: Copyright (c) 2025 NVIDIA CORPORATION & AFFILIATES. All rights reserved.
SPDX-License-Identifier: Apache-2.0
-->

# Skill: Coordination

Read this when multiple agents need to share state without conflicts.

## The Problem

Multiple agents write to the same git branch. If two agents modify the same file, git conflicts break everything.

## The Solution: One Writer Per File

State files live in `.agent/` in git. The rule: **each file has exactly one writer at any given time.**

```
.agent/
├── task.json              # Written once by root. Immutable after.
├── subtasks/
│   ├── st-001.json        # Created by parent. OWNED by st-001's agent after creation.
│   ├── st-002.json        # Created by parent. OWNED by st-002's agent.
│   └── st-002-a.json      # Created by st-002's agent. OWNED by st-002-a's agent.
└── decisions/
    ├── d-001.json          # Written once. Immutable.
    └── d-002.json
```

- **Parent creates** the subtask file (defines the mandate)
- **Child owns** the subtask file (updates status, records progress)
- **Parent reads** the file to check status, but never writes to it after creation
- **Decision files** are written once when a human answers a question. Everyone reads them.

## Why This Works for Parallel Planning

During planning, multiple children can run simultaneously. Each writes to its own subtask file. `git pull --rebase` before push succeeds because the files don't overlap.

## Why Code Changes Must Be Sequential

Code files ARE interdependent. Two agents editing different files can still break each other (shared imports, test dependencies). The only safe approach: one agent modifies code at a time, validates, then the next agent starts from the validated state.

## Reading Full State

Any agent can assemble the big picture by scanning:

```bash
cat .agent/task.json
for f in .agent/subtasks/st-*.json; do jq '{id:.id, status:.status}' "$f"; done
for f in .agent/decisions/d-*.json; do jq '.decision' "$f"; done
```

## Cross-Cutting Concerns

If you discover something that affects multiple subtasks (e.g., "every model needs a compatibility wrapper"), don't implement it across files you don't own. Write a decision file in `.agent/decisions/` describing the pattern. All subsequent agents read decisions on startup and apply them consistently.
