# V5Python Converter

Convert between `.v5python` (JSON) format and normal Python files for VEXcode V5 projects.

## Usage

### Convert .v5python to Python

```bash
./convert_v5python.py prototype-auto.v5python -o output.py
```

### Convert Python to .v5python

```bash
./convert_v5python.py output.py -o output.v5python
```

### Preserve metadata with template

When converting Python back to `.v5python`, use `--template` to preserve original metadata (sounds, AI vision settings, etc.):

```bash
./convert_v5python.py output.py -o output.v5python --template prototype-auto.v5python
```

### Output to stdout

Omit `-o` to output to stdout:

```bash
./convert_v5python.py prototype-auto.v5python
```

## Options

- `-o, --output`: Output file path (default: stdout)
- `--to-python`: Force conversion to Python (default: auto-detect by extension)
- `--to-v5python`: Force conversion to .v5python (default: auto-detect by extension)
- `--template`: Template .v5python file to use when converting Python -> .v5python

## Auto-detection

The script automatically detects the conversion direction based on file extension:
- `.v5python` → Python
- `.py` → .v5python

Use `--to-python` or `--to-v5python` to override auto-detection.

## Error Handling

The script validates JSON structure and provides clear error messages for:
- Invalid JSON syntax
- Missing `textContent` field
- File read/write errors

