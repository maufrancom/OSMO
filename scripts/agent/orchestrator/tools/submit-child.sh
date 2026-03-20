#!/usr/bin/env bash
# SPDX-FileCopyrightText: Copyright (c) 2025 NVIDIA CORPORATION & AFFILIATES. All rights reserved.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
# http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#
# SPDX-License-Identifier: Apache-2.0

# Submit a child OSMO workflow for a specific module/subtask.
#
# Usage: submit-child.sh <module> <files-csv> <description>
#
# Reads the child workflow and prompt templates, substitutes placeholders,
# and submits the rendered workflow via the OSMO CLI.
#
# Environment variables (required):
#   GITHUB_REPO       - Repository URL
#   BRANCH_NAME       - Git branch to work on
#   KNOWLEDGE_DOC     - Path or content of the knowledge document
#   COMMIT_PREFIX     - Prefix for commit messages
#
# Environment variables (optional):
#   LEARNED_DECISIONS - Accumulated decisions from prior subtasks (may be empty)

set -euo pipefail

if [[ $# -lt 3 ]]; then
  echo "Usage: submit-child.sh <module> <files-csv> <description>" >&2
  echo "" >&2
  echo "  module       Short identifier for the subtask (e.g., lib-utils)" >&2
  echo "  files-csv    Comma-separated file paths relative to repo root" >&2
  echo "  description  One-sentence description of the child's task" >&2
  exit 1
fi

MODULE="$1"
FILES_CSV="$2"
DESCRIPTION="$3"

# Validate required environment variables
for var in GITHUB_REPO BRANCH_NAME KNOWLEDGE_DOC COMMIT_PREFIX; do
  if [[ -z "${!var:-}" ]]; then
    echo "ERROR: Required environment variable $var is not set." >&2
    exit 1
  fi
done

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ORCHESTRATOR_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

WORKFLOW_TEMPLATE="$ORCHESTRATOR_DIR/child-workflow-template.yaml"
PROMPT_TEMPLATE="$ORCHESTRATOR_DIR/child-prompt.md"

if [[ ! -f "$WORKFLOW_TEMPLATE" ]]; then
  echo "ERROR: Child workflow template not found at $WORKFLOW_TEMPLATE" >&2
  exit 1
fi

if [[ ! -f "$PROMPT_TEMPLATE" ]]; then
  echo "ERROR: Child prompt template not found at $PROMPT_TEMPLATE" >&2
  exit 1
fi

# Sanitize module name for OSMO workflow naming: replace / with -, lowercase
SANITIZED_MODULE=$(echo "$MODULE" | tr '/' '-' | tr '[:upper:]' '[:lower:]')

# Convert comma-separated files to a markdown list (one per line with "- " prefix)
FILES_LIST=""
IFS=',' read -ra FILE_ARRAY <<< "$FILES_CSV"
for file in "${FILE_ARRAY[@]}"; do
  trimmed=$(echo "$file" | xargs)
  if [[ -n "$trimmed" ]]; then
    FILES_LIST="${FILES_LIST}- ${trimmed}"$'\n'
  fi
done
# Remove trailing newline
FILES_LIST="${FILES_LIST%$'\n'}"

LEARNED_DECISIONS="${LEARNED_DECISIONS:-}"

# Render the prompt template with placeholder substitution
RENDERED_PROMPT=$(cat "$PROMPT_TEMPLATE")
RENDERED_PROMPT="${RENDERED_PROMPT//__MODULE__/$MODULE}"
RENDERED_PROMPT="${RENDERED_PROMPT//__GITHUB_REPO__/$GITHUB_REPO}"
RENDERED_PROMPT="${RENDERED_PROMPT//__BRANCH__/$BRANCH_NAME}"
RENDERED_PROMPT="${RENDERED_PROMPT//__DESCRIPTION__/$DESCRIPTION}"
RENDERED_PROMPT="${RENDERED_PROMPT//__COMMIT_PREFIX__/$COMMIT_PREFIX}"
RENDERED_PROMPT="${RENDERED_PROMPT//__FILES_LIST__/$FILES_LIST}"
RENDERED_PROMPT="${RENDERED_PROMPT//__KNOWLEDGE_DOC__/$KNOWLEDGE_DOC}"
RENDERED_PROMPT="${RENDERED_PROMPT//__LEARNED_DECISIONS__/$LEARNED_DECISIONS}"

# Render the workflow template
RENDERED_WORKFLOW=$(cat "$WORKFLOW_TEMPLATE")
RENDERED_WORKFLOW="${RENDERED_WORKFLOW//__MODULE__/$SANITIZED_MODULE}"
RENDERED_WORKFLOW="${RENDERED_WORKFLOW//__GITHUB_REPO__/$GITHUB_REPO}"
RENDERED_WORKFLOW="${RENDERED_WORKFLOW//__BRANCH__/$BRANCH_NAME}"
RENDERED_WORKFLOW="${RENDERED_WORKFLOW//__DESCRIPTION__/$DESCRIPTION}"
RENDERED_WORKFLOW="${RENDERED_WORKFLOW//__COMMIT_PREFIX__/$COMMIT_PREFIX}"
RENDERED_WORKFLOW="${RENDERED_WORKFLOW//__FILES_LIST__/$FILES_LIST}"
RENDERED_WORKFLOW="${RENDERED_WORKFLOW//__KNOWLEDGE_DOC__/$KNOWLEDGE_DOC}"
RENDERED_WORKFLOW="${RENDERED_WORKFLOW//__LEARNED_DECISIONS__/$LEARNED_DECISIONS}"

# Insert the rendered prompt into the workflow YAML
RENDERED_WORKFLOW="${RENDERED_WORKFLOW//__PROMPT_CONTENTS__/$RENDERED_PROMPT}"

# Write to a temp file
TEMP_FILE=$(mktemp /tmp/osmo-child-workflow-XXXXXX.yaml)
trap 'rm -f "$TEMP_FILE"' EXIT

echo "$RENDERED_WORKFLOW" > "$TEMP_FILE"

# Submit the workflow and capture the workflow ID
OUTPUT=$(osmo workflow submit "$TEMP_FILE" 2>&1)

# Extract the workflow ID from the output.
# The osmo CLI typically prints a line containing the workflow ID.
WORKFLOW_ID=$(echo "$OUTPUT" | grep -oE '[a-f0-9-]{36}' | head -1)

if [[ -z "$WORKFLOW_ID" ]]; then
  echo "ERROR: Failed to extract workflow ID from osmo output:" >&2
  echo "$OUTPUT" >&2
  exit 1
fi

echo "$WORKFLOW_ID"
