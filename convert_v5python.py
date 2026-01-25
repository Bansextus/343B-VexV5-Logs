#!/usr/bin/env python3
"""
Convert between .v5python (JSON) format and normal Python files.
"""

import json
import sys
import argparse
from pathlib import Path


def v5python_to_python(v5python_path, output_path=None):
    """Extract Python code from .v5python JSON file."""
    try:
        with open(v5python_path, 'r', encoding='utf-8') as f:
            data = json.load(f)
    except json.JSONDecodeError as e:
        print(f"Error: Invalid JSON in {v5python_path}: {e}", file=sys.stderr)
        sys.exit(1)
    except Exception as e:
        print(f"Error reading {v5python_path}: {e}", file=sys.stderr)
        sys.exit(1)
    
    if 'textContent' not in data:
        print(f"Error: Missing 'textContent' field in {v5python_path}", file=sys.stderr)
        sys.exit(1)
    
    python_code = data['textContent']
    
    try:
        if output_path:
            with open(output_path, 'w', encoding='utf-8') as f:
                f.write(python_code)
            print(f"Converted {v5python_path} -> {output_path}")
        else:
            print(python_code, end='')
    except BrokenPipeError:
        pass
    except Exception as e:
        print(f"Error writing output: {e}", file=sys.stderr)
        sys.exit(1)
    
    return python_code


def python_to_v5python(python_path, output_path=None, template_path=None):
    """Wrap Python code in .v5python JSON format."""
    try:
        with open(python_path, 'r', encoding='utf-8') as f:
            python_code = f.read()
    except Exception as e:
        print(f"Error reading {python_path}: {e}", file=sys.stderr)
        sys.exit(1)
    
    if template_path and Path(template_path).exists():
        try:
            with open(template_path, 'r', encoding='utf-8') as f:
                template = json.load(f)
        except json.JSONDecodeError as e:
            print(f"Error: Invalid JSON in template {template_path}: {e}", file=sys.stderr)
            sys.exit(1)
        except Exception as e:
            print(f"Error reading template {template_path}: {e}", file=sys.stderr)
            sys.exit(1)
        template['textContent'] = python_code
        data = template
    else:
        data = {
            "mode": "Text",
            "hardwareTarget": "brain",
            "textContent": python_code,
            "textLanguage": "python",
            "robotConfig": [],
            "slot": 4,
            "platform": "V5",
            "sdkVersion": "20240802.15.00.00",
            "appVersion": "4.62.0",
            "fileFormat": "2.0.0",
            "targetBrainGen": "First",
            "v5Sounds": [],
            "v5SoundsEnabled": False,
            "aiVisionSettings": {
                "colors": [],
                "codes": [],
                "tags": True,
                "AIObjects": True,
                "AIObjectModel": [],
                "aiModelDropDownValue": None
            }
        }
    
    try:
        if output_path:
            with open(output_path, 'w', encoding='utf-8') as f:
                json.dump(data, f, indent=2)
            print(f"Converted {python_path} -> {output_path}")
        else:
            print(json.dumps(data, indent=2), end='')
    except BrokenPipeError:
        pass
    except Exception as e:
        print(f"Error writing output: {e}", file=sys.stderr)
        sys.exit(1)
    
    return data


def main():
    parser = argparse.ArgumentParser(
        description='Convert between .v5python (JSON) and normal Python files'
    )
    parser.add_argument('input_file', help='Input file path')
    parser.add_argument('-o', '--output', help='Output file path (default: stdout)')
    parser.add_argument(
        '--to-python',
        action='store_true',
        help='Convert .v5python to Python (default: auto-detect)'
    )
    parser.add_argument(
        '--to-v5python',
        action='store_true',
        help='Convert Python to .v5python (default: auto-detect)'
    )
    parser.add_argument(
        '--template',
        help='Template .v5python file to use when converting Python -> .v5python'
    )
    
    args = parser.parse_args()
    
    input_path = Path(args.input_file)
    
    if not input_path.exists():
        print(f"Error: {input_path} does not exist", file=sys.stderr)
        sys.exit(1)
    
    if args.to_python and args.to_v5python:
        print("Error: Cannot specify both --to-python and --to-v5python", file=sys.stderr)
        sys.exit(1)
    
    if args.to_python or input_path.suffix == '.v5python':
        v5python_to_python(input_path, args.output)
    elif args.to_v5python or input_path.suffix == '.py':
        python_to_v5python(input_path, args.output, args.template)
    else:
        print("Error: Cannot auto-detect format. Use --to-python or --to-v5python", file=sys.stderr)
        sys.exit(1)


if __name__ == '__main__':
    main()

