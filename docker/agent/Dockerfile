# SPDX-FileCopyrightText: Copyright (c) 2025 NVIDIA CORPORATION & AFFILIATES. All rights reserved.
# SPDX-License-Identifier: Apache-2.0

# OSMO Agent Image
#
# General-purpose agent environment. Ships with common build tools and package
# managers. The agent discovers what the repo needs and installs/configures
# the correct runtime (Python version, Go version, etc.) as part of its
# discovery phase.
#
# Build (from repo root):
#   docker build -t osmo-agent:latest -f docker/agent/Dockerfile .

FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive

# System tools + build essentials + deadsnakes PPA (for any Python version)
RUN apt-get update -qq && \
    apt-get install -y -qq --no-install-recommends \
      git \
      jq \
      curl \
      ca-certificates \
      openssh-client \
      build-essential \
      software-properties-common \
      sudo \
      python3 \
      python3-pip \
      python3-dev \
    && add-apt-repository -y ppa:deadsnakes/ppa \
    && rm -rf /var/lib/apt/lists/*

# GitHub CLI
RUN curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
      -o /usr/share/keyrings/githubcli-archive-keyring.gpg && \
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
      > /etc/apt/sources.list.d/github-cli.list && \
    apt-get update -qq && \
    apt-get install -y -qq --no-install-recommends gh && \
    rm -rf /var/lib/apt/lists/*

# Bazel 8.1.1
RUN curl -fsSL "https://github.com/bazelbuild/bazel/releases/download/8.1.1/bazel-8.1.1-linux-x86_64" \
      -o /usr/local/bin/bazel && \
    chmod +x /usr/local/bin/bazel

# Python tools for the harness itself (runs on system python3)
RUN pip3 install --break-system-packages openai ruff pip-tools

# Non-root user with passwordless sudo (needs root for runtime package installs)
RUN useradd -m -s /bin/bash agent && \
    echo "agent ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/agent && \
    mkdir -p /workspace && \
    chown -R agent:agent /workspace

# OSMO runtime bin path
ENV PATH="/osmo/usr/bin:${PATH}"

# --- Bake in the static framework ---
COPY --chown=agent:agent scripts/agent/orchestrator/orchestrator-prompt.md /osmo/agent/orchestrator-prompt.md
COPY --chown=agent:agent scripts/agent/orchestrator/orchestrator.yaml      /osmo/agent/orchestrator.yaml
COPY --chown=agent:agent scripts/agent/orchestrator/tools/                 /osmo/agent/tools/
COPY --chown=agent:agent scripts/agent/orchestrator/skills/                /osmo/agent/skills/
COPY --chown=agent:agent scripts/agent/orchestrator/agent-harness.py       /osmo/agent/agent-harness.py
RUN chmod +x /osmo/agent/tools/*.sh

USER agent
WORKDIR /workspace

RUN git config --global init.defaultBranch main && \
    git config --global advice.detachedHead false

ENTRYPOINT ["/bin/bash"]
