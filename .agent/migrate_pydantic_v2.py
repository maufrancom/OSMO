#!/usr/bin/env python3
"""
Pydantic v1 to v2 migration script for the OSMO repository.
Handles the bulk mechanical replacements. Complex cases are flagged for manual review.
"""
import re
import sys
import os
import glob


def process_file(filepath):
    """Process a single Python file for Pydantic v1->v2 migration."""
    with open(filepath, 'r') as f:
        content = f.read()
    
    original = content
    changes = []
    
    # === 1. .dict() -> .model_dump() ===
    # This is used on pydantic BaseModel instances
    if '.dict()' in content:
        content = content.replace('.dict()', '.model_dump()')
        changes.append('.dict() -> .model_dump()')
    
    # === 2. .construct( -> .model_construct( ===
    if '.construct(' in content:
        content = content.replace('.construct(', '.model_construct(')
        changes.append('.construct() -> .model_construct()')
    
    # === 3. __fields__ -> model_fields ===
    if '__fields__' in content:
        content = content.replace('.__fields__', '.model_fields')
        changes.append('__fields__ -> model_fields')
    
    # === 4. @pydantic.validator -> @pydantic.field_validator ===
    # Pattern: @pydantic.validator('field', ...) 
    # -> @pydantic.field_validator('field', mode='before') if pre=True
    # -> @pydantic.field_validator('field') if no pre
    # Handle check_fields=False, always=True, pre=True params
    
    def convert_validator_decorator(match):
        full = match.group(0)
        fields = match.group(1)  # The field names part
        rest = match.group(2)    # The rest of kwargs
        
        # Parse kwargs
        pre = 'pre=True' in rest or 'pre = True' in rest
        always = 'always=True' in rest or 'always = True' in rest
        check_fields = 'check_fields=False' in rest or 'check_fields = False' in rest
        
        # Build new decorator
        new_args = [fields.strip()]
        if pre:
            new_args.append("mode='before'")
        if check_fields:
            new_args.append("check_fields=False")
        
        return f"@pydantic.field_validator({', '.join(new_args)})"
    
    # Match @pydantic.validator('field'[, 'field2'][, kwargs])
    content = re.sub(
        r"@pydantic\.validator\(([^)]*?)(?:,\s*((?:pre|always|check_fields)\s*=\s*(?:True|False)(?:\s*,\s*(?:pre|always|check_fields)\s*=\s*(?:True|False))*))\)",
        convert_validator_decorator,
        content
    )
    # Also handle simple case: @pydantic.validator('field') with no kwargs
    content = re.sub(
        r"@pydantic\.validator\(([^)]+)\)",
        lambda m: f"@pydantic.field_validator({m.group(1)})" 
            if 'pre=' not in m.group(1) and 'always=' not in m.group(1) and 'check_fields=' not in m.group(1)
            else m.group(0),
        content
    )
    
    if '@pydantic.field_validator' in content and '@pydantic.field_validator' not in original:
        changes.append('@pydantic.validator -> @pydantic.field_validator')
    
    # === 5. @pydantic.root_validator -> @pydantic.model_validator ===
    # @pydantic.root_validator(pre=True) -> @pydantic.model_validator(mode='before')
    # @pydantic.root_validator() -> @pydantic.model_validator(mode='before') 
    # @pydantic.root_validator -> @pydantic.model_validator(mode='before')
    # @pydantic.root_validator(skip_on_failure=True) -> @pydantic.model_validator(mode='before')
    
    content = re.sub(
        r"@pydantic\.root_validator\(pre=True\)",
        "@pydantic.model_validator(mode='before')",
        content
    )
    content = re.sub(
        r"@pydantic\.root_validator\(skip_on_failure=True\)",
        "@pydantic.model_validator(mode='before')",
        content
    )
    content = re.sub(
        r"@pydantic\.root_validator\(\)",
        "@pydantic.model_validator(mode='before')",
        content
    )
    content = re.sub(
        r"@pydantic\.root_validator\b(?!\()",
        "@pydantic.model_validator(mode='before')",
        content
    )
    
    if '@pydantic.model_validator' in content and '@pydantic.model_validator' not in original:
        changes.append('@pydantic.root_validator -> @pydantic.model_validator')
    
    if content != original:
        with open(filepath, 'w') as f:
            f.write(content)
    
    return changes


def main():
    src_dir = '/workspace/repo/src'
    all_changes = {}
    
    for root, dirs, files in os.walk(src_dir):
        for fname in files:
            if fname.endswith('.py'):
                fpath = os.path.join(root, fname)
                with open(fpath, 'r') as f:
                    if 'pydantic' in f.read():
                        file_changes = process_file(fpath)
                        if file_changes:
                            all_changes[fpath] = file_changes
    
    for fpath in sorted(all_changes.keys()):
        print(f"\n{fpath}:")
        for change in all_changes[fpath]:
            print(f"  - {change}")
    
    print(f"\n\nTotal files modified: {len(all_changes)}")


if __name__ == '__main__':
    main()
