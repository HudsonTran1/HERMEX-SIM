#!/usr/bin/env bash
set -eo pipefail

# Define Base Paths
WORKSPACE_DIR="/workspace"
PATCHFILES_DIR="$WORKSPACE_DIR/patchfiles"
RAMULATOR_DIR="$WORKSPACE_DIR/ramulator2"

echo "=========================================================="
echo "         Starting Ramulator 2 & SST Setup                "
echo "=========================================================="

# ------------------------------------------------------------------
# Step 0: Sanity Checks & Workspace Validation
# ------------------------------------------------------------------
if [ ! -d "$RAMULATOR_DIR" ]; then
    echo "❌ Error: Ramulator directory not found at $RAMULATOR_DIR"
    exit 1
fi

if [ ! -d "$PATCHFILES_DIR" ]; then
    echo "❌ Error: Patchfiles directory not found at $PATCHFILES_DIR"
    exit 1
fi

# ------------------------------------------------------------------
# Step 1: Copy Source Files from /workspace/patchfiles
# ------------------------------------------------------------------
echo "[1/5] Copying new source files into Ramulator 2 repository..."

# Copy sst_frontend.cpp to /src/ramulator/frontend/impl/external_wrapper
mkdir -p "$RAMULATOR_DIR/src/ramulator/frontend/impl/external_wrapper"
if [ -f "$PATCHFILES_DIR/sst_frontend.cpp" ]; then
    cp "$PATCHFILES_DIR/sst_frontend.cpp" "$RAMULATOR_DIR/src/ramulator/frontend/impl/external_wrapper/"
    echo "  -> Copied sst_frontend.cpp"
else
    echo "  ⚠️ Warning: $PATCHFILES_DIR/sst_frontend.cpp not found!"
fi

# Copy sedram.py into python/ramulator/dram
mkdir -p "$RAMULATOR_DIR/python/ramulator/dram"
if [ -f "$PATCHFILES_DIR/sedram.py" ]; then
    cp "$PATCHFILES_DIR/sedram.py" "$RAMULATOR_DIR/python/ramulator/dram/"
    echo "  -> Copied sedram.py"
else
    echo "  ⚠️ Warning: $PATCHFILES_DIR/sedram.py not found!"
fi

# ------------------------------------------------------------------
# Step 2: Install Python Module & Auto-generate SeDRAM.cpp
# ------------------------------------------------------------------
echo "[2/5] Installing Python module & auto-generating SeDRAM.cpp..."

cd "$RAMULATOR_DIR"

# Dynamically export user site-packages path to resolve user-level pip installs
export PYTHONUSERBASE="/home/sstuser/.local"
PYTHON_VERSION=$(python3 -c "import sys; print(f'{sys.version_info.major}.{sys.version_info.minor}')")
export PYTHONPATH="$RAMULATOR_DIR/python:$RAMULATOR_DIR:$PYTHONUSERBASE/lib/python$PYTHON_VERSION/site-packages:$PYTHONPATH"
export PATH="$PYTHONUSERBASE/bin:$PATH"

# Install package in editable mode
pip install -e . --no-build-isolation || python3 -m pip install -e .

DRAM_IMPL_DIR="$RAMULATOR_DIR/src/ramulator/dram/impl"
mkdir -p "$DRAM_IMPL_DIR"

# Run codegen
python3 -m ramulator codegen SeDRAM

# Verify SeDRAM.cpp was generated properly into src/ramulator/dram/impl
if [ -s "$DRAM_IMPL_DIR/SeDRAM.cpp" ]; then
    echo "  -> Successfully generated $DRAM_IMPL_DIR/SeDRAM.cpp"
else
    echo "❌ Error: Codegen completed but $DRAM_IMPL_DIR/SeDRAM.cpp was not created."
    exit 1
fi

# ------------------------------------------------------------------
# Step 3: Modify CMakeLists.txt and Source Files
# ------------------------------------------------------------------
echo "[3/5] Patching CMakeLists and source code..."

# Modify root/frontend CMakeLists.txt to include sst_frontend.cpp
FRONTEND_CMAKE="$RAMULATOR_DIR/src/ramulator/frontend/CMakeLists.txt"
if [ -f "$FRONTEND_CMAKE" ]; then
    if ! grep -q "impl/external_wrapper/sst_frontend.cpp" "$FRONTEND_CMAKE"; then
        sed -i '/impl\/external.cpp/a \    impl\/external_wrapper\/sst_frontend.cpp' "$FRONTEND_CMAKE"
        echo "  -> Updated $FRONTEND_CMAKE"
    else
        echo "  -> $FRONTEND_CMAKE already updated."
    fi
fi

# Modify src/ramulator/dram/CMakeLists.txt to include SeDRAM.cpp
DRAM_CMAKE="$RAMULATOR_DIR/src/ramulator/dram/CMakeLists.txt"
if [ -f "$DRAM_CMAKE" ]; then
    if ! grep -q "impl/SeDRAM.cpp" "$DRAM_CMAKE"; then
        sed -i '/commands\/populate.h/a \    impl\/SeDRAM.cpp' "$DRAM_CMAKE"
        echo "  -> Updated $DRAM_CMAKE"
    else
        echo "  -> $DRAM_CMAKE already updated."
    fi
fi

# Modify src/ramulator/controller/refresh/impl/all_bank.cpp for SeDRAM
ALL_BANK_CPP="$RAMULATOR_DIR/src/ramulator/controller/refresh/impl/all_bank.cpp"
if [ -f "$ALL_BANK_CPP" ]; then
    sed -i 's/std::array<std::pair<std::string_view, std::string_view>, 11>/std::array<std::pair<std::string_view, std::string_view>, 12>/g' "$ALL_BANK_CPP"
    
    if ! grep -q '"SeDRAM", "BankGroup"' "$ALL_BANK_CPP"; then
        sed -i '/{"HBM4", "PseudoChannel"},/a \        {"SeDRAM", "BankGroup"},' "$ALL_BANK_CPP"
        echo "  -> Updated $ALL_BANK_CPP"
    else
        echo "  -> $ALL_BANK_CPP already updated."
    fi
fi

# ------------------------------------------------------------------
# Step 4: Build Ramulator 2
# ------------------------------------------------------------------
echo "[4/5] Building Ramulator 2 using CMake..."
BUILD_DIR="$RAMULATOR_DIR/build"
mkdir -p "$BUILD_DIR"
cd "$BUILD_DIR"

cmake ..
make -j"$(nproc)"

echo "=========================================================="
echo "           Ramulator 2 Setup Complete!                    "
echo "=========================================================="