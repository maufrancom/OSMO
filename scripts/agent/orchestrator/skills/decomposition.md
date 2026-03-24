<!--
SPDX-FileCopyrightText: Copyright (c) 2025 NVIDIA CORPORATION & AFFILIATES. All rights reserved.
SPDX-License-Identifier: Apache-2.0
-->

# Skill: Decomposition

Read this when the task is too large to do in one shot.

## When to Decompose

Decompose when you can't hold all the context in your head, or when the scope spans multiple independent modules. Don't decompose for the sake of it — a 10-file change in one module is better done in one pass than split into 3 subtasks.

## How to Decompose

**By module boundary**: One service, one library, one package. These are natural units with internal cohesion.

**By dependency layer**: Shared libraries before consumers. If `lib/utils` changes, everything that imports from it needs to come after.

**By logical grouping**: Sometimes files that span directories belong together — a data model and all its serializers, for example.

## Invariants

- **No overlapping files**: Two subtasks must never list the same file. If a file needs changes from two subtasks, put it in the earlier one.
- **Dependencies are explicit**: If subtask B depends on subtask A's changes, record that.
- **Scope must reduce**: If you delegate a subtask to a child, the child's file count must be strictly less than yours. This guarantees the hierarchy terminates.

## Writing the Plan

If you decompose, write your plan to `.agent/subtasks/` so other agents (and future sessions) can understand it. Each subtask gets its own file — the format is up to you, but include at minimum:
- An ID
- The scope (which module/files)
- Status (pending, in_progress, executed, blocked)
- Dependencies (which subtasks must complete first)

See `coordination.md` for how multiple agents share state without conflicts.
