<!--
SPDX-FileCopyrightText: Copyright (c) 2025 NVIDIA CORPORATION & AFFILIATES. All rights reserved.
SPDX-License-Identifier: Apache-2.0
-->

# Skill: Delegation

Read this when you decide to spawn child agent workflows.

## How It Works

You submit a child workflow using the same image and prompt as yourself. The only difference is the `SUBTASK_ID` — it tells the child which subtask in `.agent/subtasks/` to work on.

```bash
# Submit a child for subtask st-004
/osmo/agent/tools/submit-child.sh "st-004" "utils-connectors"
# Returns a workflow ID

# Wait for it
/osmo/agent/tools/poll-workflow.sh <workflow-id>
# Exit 0 = done, 1 = failed, 2 = timeout
```

The child clones the repo, checks out the same branch, reads `.agent/subtasks/st-004.json`, and works on it. If the child decides the scope is still too large, it can decompose further and delegate to grandchildren. Same pattern, recursive.

## Before Delegating

1. **Create the subtask file** in `.agent/subtasks/` with the child's mandate
2. **Commit and push** so the child can read it after cloning
3. **Submit the child** via `submit-child.sh`

## After Child Completes

1. `git pull` to get the child's code changes and updated subtask file
2. Validate — run quality gates on the combined state
3. If validation fails, decide: retry the child with error context, or ask a human

## Code Changes Are Sequential

If you're delegating multiple subtasks that all modify code, submit them one at a time. Each child must start from the last validated state. This is because code is interdependent — tests validate everything together.

Planning and validation children can run in parallel because they don't modify code.

## Cycle Detection

Track ancestry in each subtask file. If a child's scope matches any ancestor's scope, something is wrong — the decomposition is circular. Execute directly instead.
