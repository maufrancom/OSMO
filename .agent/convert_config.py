#!/usr/bin/env python3
"""Convert class Config: inner classes to model_config = ConfigDict(...)"""

import re
import sys

# Map of v1 Config attributes to v2 ConfigDict keys
CONFIG_KEY_MAP = {
    'use_enum_values': 'use_enum_values',
    'extra': 'extra',
    'arbitrary_types_allowed': 'arbitrary_types_allowed',
    'frozen': 'frozen',
    'validate_assignment': 'validate_assignment',
    'keep_untouched': 'ignored_types',
    'allow_population_by_field_name': 'populate_by_name',
    'populate_by_name': 'populate_by_name',
    'allow_extra': None,  # not a standard pydantic v2 option, handle specially
    'ignore_extra': None,  # not a standard pydantic v2 option, handle specially
}

def convert_file(filepath):
    with open(filepath) as f:
        content = f.read()
    
    original = content
    
    # Pattern to match class Config: blocks
    # Matches from "class Config:" to the next unindented line at the same level
    pattern = r'(\n([ \t]+))class Config:\n((?:(?:\2[ \t]+[^\n]*|\s*#[^\n]*|\s*)\n)*)'
    
    def replace_config(match):
        prefix_newline = match.group(1)  # \n + indentation
        indent = match.group(2)  # indentation
        body = match.group(3)  # body of Config class
        
        # Parse the body for key=value pairs
        config_items = []
        for line in body.split('\n'):
            stripped = line.strip()
            if not stripped or stripped.startswith('#') or stripped.startswith('"""') or stripped.startswith("'''"):
                continue
            # Match simple assignments like: key = value
            m = re.match(r'(\w+)\s*=\s*(.+)', stripped)
            if m:
                key = m.group(1)
                value = m.group(2).strip()
                v2_key = CONFIG_KEY_MAP.get(key, key)
                if v2_key is not None:
                    config_items.append((v2_key, value))
        
        if not config_items:
            return match.group(0)  # Don't convert if we can't parse
        
        items_str = ', '.join(f'{k}={v}' for k, v in config_items)
        return f'{prefix_newline}model_config = pydantic.ConfigDict({items_str})\n'
    
    content = re.sub(pattern, replace_config, content)
    
    if content != original:
        with open(filepath, 'w') as f:
            f.write(content)
        print(f'Updated: {filepath}')
    else:
        print(f'No changes: {filepath}')

if __name__ == '__main__':
    for filepath in sys.argv[1:]:
        convert_file(filepath)
