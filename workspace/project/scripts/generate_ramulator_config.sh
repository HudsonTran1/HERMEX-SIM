#!/usr/bin/env bash
set -e

CONFIGS_DIR="/workspace/project/ramulator_configs"
OUTPUT_YAML="$CONFIGS_DIR/ramulator_config.yaml"
RAMULATOR_DIR="/workspace/ramulator2"

# 1. Verify that the .so library exists inside Ramulator 2 directory
SO_FILE=$(find "$RAMULATOR_DIR" -type f -name "*.so" | head -n 1)

if [ -z "$SO_FILE" ]; then
    echo "Error: No compiled .so library found in '$RAMULATOR_DIR'."
    echo "Make sure to run 'cmake .. && make' inside /workspace/ramulator2/build."
    exit 1
fi

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

# 5. Set PYTHONPATH to include Ramulator 2 python directory
export PYTHONPATH="$RAMULATOR_DIR/python:${PYTHONPATH:-}"

# 6. Capture configuration and export to YAML using native Ramulator 2 exporter
python3 -c "
import sys
sys.path.insert(0, '$RAMULATOR_DIR/python')

import ramulator.export

config_dict = ramulator.export.capture_config('$SELECTED_PY')
yaml_str = ramulator.export.dict_to_yaml(config_dict)

with open('$OUTPUT_YAML', 'w') as f:
    f.write(yaml_str)
"

echo "------------------------------------------"
echo "✅ Successfully updated: $OUTPUT_YAML"