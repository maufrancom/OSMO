# Episode 006: Fix line-too-long in operator/utils/objects.py

## Date: 2026-03-26

## Task
Fix remaining pylint line-too-long issues in `src/operator/utils/objects.py` after removing `required=True` from Pydantic v2 Field() calls.

## What Was Done
1. Broke long `json_schema_extra` dicts across multiple lines (putting each key-value on its own line)
2. Broke long `description` strings using Python implicit string concatenation
3. Verified all lines are under 100 characters

## Outcome
- All 131 tests pass (unit tests + pylint + mypy)
- Successfully pushed to branch

## Key Patterns
- Pydantic v2 doesn't accept `required=True` in Field() — fields without defaults are required by default
- `json_schema_extra={'key': 'val', 'key2': 'val2'}` can be reformatted as multi-line dict to stay under 100 chars
- Python implicit string concatenation (`'part1' + newline + 'part2'` or `('part1' 'part2')`) works inside function argument lists
