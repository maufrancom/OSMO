# SPDX-FileCopyrightText: Copyright (c) 2025 NVIDIA CORPORATION & AFFILIATES. All rights reserved.
# SPDX-License-Identifier: Apache-2.0

# OSMO Agent Image
#
# Purpose-built image for all agent workflows (orchestrator + children).
# Contains the static framework (prompt, tools, workflow template) baked in.
# Dynamic content (knowledge docs, code, state) comes from git at runtime.
#
# Build (from repo root):
#   docker build -t osmo-agent:latest -f docker/agent/Dockerfile .
#
# What's baked in (static framework):
#   /osmo/agent/orchestrator-prompt.md   — the meta-prompt
#   /osmo/agent/orchestrator.yaml        — unified workflow template
#   /osmo/agent/tools/*.sh               — DIF infrastructure scripts
#
# What's provided by OSMO runtime (not in image):
#   /osmo/usr/bin/osmo                   — OSMO CLI
#
# What comes from git at runtime (dynamic):
#   Knowledge docs, AGENTS.md, source code, .agent/ state

FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive

# System tools
RUN apt-get update -qq && \
    apt-get install -y -qq --no-install-recommends \
      git \
      jq \
      curl \
      python3 \
      python3-yaml \
      ca-certificates \
      openssh-client \
    && rm -rf /var/lib/apt/lists/*

# GitHub CLI
RUN curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
      -o /usr/share/keyrings/githubcli-archive-keyring.gpg && \
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
      > /etc/apt/sources.list.d/github-cli.list && \
    apt-get update -qq && \
    apt-get install -y -qq --no-install-recommends gh && \
    rm -rf /var/lib/apt/lists/*

# Node.js (required for Claude Code)
RUN curl -fsSL https://deb.nodesource.com/setup_22.x | bash - && \
    apt-get install -y -qq --no-install-recommends nodejs && \
    rm -rf /var/lib/apt/lists/*

# Claude Code CLI
RUN npm install -g @anthropic-ai/claude-code && \
    npm cache clean --force

# OSMO runtime bin path
ENV PATH="/osmo/usr/bin:${PATH}"

# --- Bake in the static framework ---
COPY scripts/agent/orchestrator/orchestrator-prompt.md /osmo/agent/orchestrator-prompt.md
COPY scripts/agent/orchestrator/orchestrator.yaml      /osmo/agent/orchestrator.yaml
COPY scripts/agent/orchestrator/tools/                 /osmo/agent/tools/
COPY scripts/agent/orchestrator/skills/                /osmo/agent/skills/
RUN chmod +x /osmo/agent/tools/*.sh

WORKDIR /workspace

RUN git config --global init.defaultBranch main && \
    git config --global advice.detachedHead false

ENTRYPOINT ["/bin/bash"]
