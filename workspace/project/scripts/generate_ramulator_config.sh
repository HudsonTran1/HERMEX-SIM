#!/usr/bin/env bash
set -e

CONFIGS_DIR="/workspace/project/ramulator_configs"
OUTPUT_YAML="$CONFIGS_DIR/ramulator_config.yaml"
RAMULATOR_DIR="/workspace/ramulator2"

# 1. Verify that the .so library exists somewhere under /workspace/ramulator2
SO_FILE=$(find "$RAMULATOR_DIR" -type f -name "*.so" | head -n 1)

if [ -z "$SO_FILE" ]; then
    echo "Error: No compiled .so library found in '$RAMULATOR_DIR'."
    echo "Make sure to run 'cmake .. && make' inside /workspace/ramulator2/build."
    exit 1
fi

# Extract directory of the found .so file to include in PYTHONPATH
SO_DIR=$(dirname "$SO_FILE")

# 2. Check if ramulator_configs directory exists
if [ ! -d "$CONFIGS_DIR" ]; then
    echo "Error: Directory '$CONFIGS_DIR' does not exist."
    exit 1
fi

# 3. Find all .py config files inside /workspace/project/ramulator_configs
mapfile -t CONFIG_FILES < <(find "$CONFIGS_DIR" -maxdepth 1 -type f -name "*.py" | sort)

if [ ${#CONFIG_FILES[@]} -eq 0 ]; then
    echo "No .py configuration files found in '$CONFIGS_DIR'."
    exit 1
fi

# 4. Prompt user to select a config file
echo "=========================================="
echo "      Ramulator 2 Config Generator        "
echo "=========================================="
echo "Found Ramulator shared library: $SO_FILE"
echo "Select a Python configuration file to convert:"
echo ""

PS3="Enter selection number (1-${#CONFIG_FILES[@]}): "
select SELECTED_PY in "${CONFIG_FILES[@]}"; do
    if [ -n "$SELECTED_PY" ]; then
        break
    else
        echo "Invalid selection."
    fi
done

echo ""
echo "Converting: $SELECTED_PY"
echo "Output path: $OUTPUT_YAML"
echo "------------------------------------------"

# 5. Export comprehensive PYTHONPATH including the .so directory, ramulator2 root, and python subfolder
export PYTHONPATH="$SO_DIR:$RAMULATOR_DIR/python:$RAMULATOR_DIR:$RAMULATOR_DIR/build:$RAMULATOR_DIR/build/src:${PYTHONPATH:-}"

# Run conversion using python and the compiled .so library
PYTHONPATH="$RAMULATOR_DIR/python:$RAMULATOR_DIR/src:$SO_DIR:${PYTHONPATH:-}" python3 "$SELECTED_PY" -dump-yaml "$OUTPUT_YAML"

echo "------------------------------------------"
echo "✅ Successfully updated: $OUTPUT_YAML"