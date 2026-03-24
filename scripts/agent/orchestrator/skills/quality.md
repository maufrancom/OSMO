<!--
SPDX-FileCopyrightText: Copyright (c) 2025 NVIDIA CORPORATION & AFFILIATES. All rights reserved.
SPDX-License-Identifier: Apache-2.0
-->

# Skill: Quality

Read this when you need to validate your work.

## Available Quality Gates

These live in the repo (not the image) because they're codebase-specific:

- **`scripts/agent/lint-fast.sh`** — Quick lint check (<5 seconds). Runs ruff (Python), go vet (Go), tsc (TypeScript) on changed files. Use after every code change.

- **`scripts/agent/quality-gate.sh`** — Full verification: architecture checks + lint + build + tests. Takes minutes. Use before declaring a task complete or after all subtasks are done.

## When to Validate

- After modifying code, before committing: at minimum run `lint-fast.sh`
- After pulling a child's changes: run `lint-fast.sh` to catch regressions
- Before declaring the entire task done: run `quality-gate.sh`

Use your judgment on how often to run the full gate vs. the fast lint. The fast lint catches most issues. The full gate catches integration issues.

## When Validation Fails

1. Read the error output carefully
2. Fix the issue yourself if you can
3. If you can't fix it after a reasonable attempt, you have options:
   - Revert: `git revert --no-edit HEAD && git push`
   - Ask a human (see `human-interaction.md`)
   - Try a different approach

Don't keep retrying the same approach. If it failed twice with similar errors, the approach is wrong.
