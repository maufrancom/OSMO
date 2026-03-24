<!--
SPDX-FileCopyrightText: Copyright (c) 2025 NVIDIA CORPORATION & AFFILIATES. All rights reserved.
SPDX-License-Identifier: Apache-2.0
-->

# Skill: Human Interaction

Read this when you're stuck and need human input.

## When to Ask

Ask only when:
- The task prompt and knowledge doc genuinely don't address the situation
- A design decision will significantly affect downstream work
- You've failed multiple times and can't determine the root cause
- You discover a systemic issue the task didn't anticipate

Don't ask when:
- You're unsure about a minor choice — follow codebase conventions
- You want confirmation that your plan is correct — just execute it
- Something failed once — try again with a different approach first
- The answer is in the codebase or knowledge doc — search harder

## How to Ask

```bash
/osmo/agent/tools/write-question.sh \
  "q-001" \
  "st-003" \
  "Context: what you were doing, what went wrong, why it matters" \
  "The specific question?" \
  '["A: Option — tradeoff", "B: Option — tradeoff", "C: Option — tradeoff"]'
```

Give the human enough context to answer without reading code. Provide concrete options — don't ask open-ended questions. State which option you'd pick if you had to decide.

## Checking for Answers

```bash
/osmo/agent/tools/check-answers.sh
# Exit 0 = answers found (printed as JSON), exit 1 = none
```

Check periodically, especially before starting a new subtask.

## After Receiving an Answer

1. Write a decision file to `.agent/decisions/d-X.json` so all future agents see it
2. Log the intervention:
   ```bash
   /osmo/agent/tools/log-intervention.sh "q-001" "design_decision" "true" '{"type":"knowledge_doc","change":"Add rule about X"}'
   ```
   Categories: `design_decision`, `ambiguity`, `bug`, `failure`, `steering`
3. Continue your work with the decision applied

## Don't Block on One Question

If you ask a question about subtask 5 but subtasks 6-10 can proceed independently, keep going. Check for the answer before you circle back to subtask 5.
