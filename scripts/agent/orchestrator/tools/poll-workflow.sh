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

# Poll a child OSMO workflow until completion, failure, or timeout.
#
# Usage: poll-workflow.sh <workflow-id> [poll-interval-seconds]
#
# Exit codes:
#   0 - Workflow completed successfully
#   1 - Workflow failed
#   2 - Timeout (30 minutes)

set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "Usage: poll-workflow.sh <workflow-id> [poll-interval-seconds]" >&2
  echo "" >&2
  echo "  workflow-id           OSMO workflow ID to poll" >&2
  echo "  poll-interval-seconds Seconds between polls (default: 30)" >&2
  exit 1
fi

WORKFLOW_ID="$1"
POLL_INTERVAL="${2:-30}"
TIMEOUT_SECONDS=1800  # 30 minutes

START_TIME=$(date +%s)

echo "Polling workflow $WORKFLOW_ID (interval: ${POLL_INTERVAL}s, timeout: ${TIMEOUT_SECONDS}s)..." >&2

while true; do
  ELAPSED=$(( $(date +%s) - START_TIME ))

  if [[ $ELAPSED -gt $TIMEOUT_SECONDS ]]; then
    echo "ERROR: Timeout after ${TIMEOUT_SECONDS}s waiting for workflow $WORKFLOW_ID" >&2
    # Attempt to get final output before exiting
    OUTPUT=$(osmo workflow query "$WORKFLOW_ID" 2>&1 || true)
    echo "$OUTPUT" | tail -50
    exit 2
  fi

  # Query the workflow status
  OUTPUT=$(osmo workflow query "$WORKFLOW_ID" 2>&1 || true)

  # Parse the status field from the output
  STATUS=$(echo "$OUTPUT" | grep -i "status" | head -1 || true)

  if echo "$STATUS" | grep -qi "COMPLETED"; then
    echo "Workflow $WORKFLOW_ID completed successfully." >&2
    echo "$OUTPUT" | tail -50
    exit 0
  fi

  if echo "$STATUS" | grep -qi "FAILED"; then
    echo "Workflow $WORKFLOW_ID failed." >&2
    echo "$OUTPUT" | tail -50
    exit 1
  fi

  echo "  [${ELAPSED}s] Status: $STATUS" >&2
  sleep "$POLL_INTERVAL"
done
