<!--
SPDX-FileCopyrightText: Copyright (c) 2025 NVIDIA CORPORATION & AFFILIATES. All rights reserved.
SPDX-License-Identifier: Apache-2.0
-->

# Skill: Preflight

**Align your container's runtime with the repo's target versions — for the runtimes relevant to your task.**

You've already discovered the repo (languages, build system, target versions). Now decide which runtimes matter for the task you've been given, and align those. A Python migration doesn't need Go aligned. A Go refactor doesn't need Node.

"Close enough" is not aligned — you must match exactly. Even if a build system manages its own toolchain, the system runtime is used for dependency resolution, lock file generation, code generation, linting, and ad-hoc scripts. You cannot predict every way the system runtime will be invoked.

## What to do

1. Based on your task prompt and discovery results, determine which runtimes are relevant.
2. For each relevant runtime, check what your container has and what the repo targets.
3. If there is a mismatch, install the correct version. You have `sudo` access. If installation fails, you are **blocked** — report it and exit.
4. Verify alignment by running the repo's build command.
5. If resuming a prior session, check whether prior work was done against the correct runtime. If not, determine what's affected.
6. Write `/tmp/environment.json`. This is a runtime artifact — do NOT commit it.
