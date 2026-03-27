<!--
SPDX-FileCopyrightText: Copyright (c) 2025 NVIDIA CORPORATION & AFFILIATES. All rights reserved.
SPDX-License-Identifier: Apache-2.0
-->

# Skill: Validate Beyond Tests

Read this after the quality gates pass. Tests passing means the test suite is green — it does not mean your changes work.

## What to think about

Ask yourself — scoped to the full task, not just this session's diff:

**Completeness**: Did you catch every instance? If you applied a pattern change across the codebase, verify it's exhaustive. One missed instance is a runtime crash waiting to happen.

**Behavioral changes**: If the task involves upgrading, migrating, or changing a dependency, understand what changed beyond the API surface. Implicit behaviors (type coercion, default values, error handling) often change silently between versions. Read the official documentation — don't rely on syntax alone.

**Runtime paths**: Do the entry points still start? Do configs load? Do error paths still work? Code that passes tests but crashes at runtime is not done.

**Consistency**: Did you verify the ENTIRE codebase is consistent with your changes — including files you didn't modify that may depend on what you changed?

## How to validate

Use the repo's own tooling. If the repo has scripts to start services, run them — don't read the scripts and manually approximate what they do. If the tooling needs dependencies, install them. The whole point of validation is to exercise the real system, not a shortcut version of it.

During discovery you may have found how to run the system locally — use it. The goal is confidence that your changes work in the real system, not just in the test harness.
