#!/usr/bin/env bash
set -eou pipefail

# ==============================================================================
# Configuration & Local Pathing Defaults
# ==============================================================================
# Sets workspace root relative to wherever you run this script ($PWD)
WORKSPACE_DIR="$(pwd)"
PROJECT_DIR="${WORKSPACE_DIR}"

echo "Working directory root set to: ${WORKSPACE_DIR}"

# ==============================================================================
# Part 1: Ramulator 2 Patching & Build
# ==============================================================================
echo "========================================================================"
echo " Part 1: Ramulator 2 Patching & Building"
echo "========================================================================"

RAMULATOR_SETUP_SCRIPT="${PROJECT_DIR}/scripts/setup_ramulator.sh"

if [ -f "$RAMULATOR_SETUP_SCRIPT" ]; then
    echo "[+] Executing setup_ramulator.sh..."
    chmod +x "$RAMULATOR_SETUP_SCRIPT"
    "$RAMULATOR_SETUP_SCRIPT"
else
    echo "[+] Applying manual patches to Ramulator 2..."
    RAM2_SRC="${WORKSPACE_DIR}/ramulator2"

    if [ ! -d "$RAM2_SRC" ]; then
        echo "[ERROR] Ramulator 2 folder not found at ${RAM2_SRC}"
        exit 1
    fi

    # I. Copy sst_frontend.cpp
    mkdir -p "${RAM2_SRC}/src/ramulator/frontend/impl/external_wrapper"
    if [ -f "${PROJECT_DIR}/patchfiles/sst_frontend.cpp" ]; then
        cp "${PROJECT_DIR}/patchfiles/sst_frontend.cpp" \
           "${RAM2_SRC}/src/ramulator/frontend/impl/external_wrapper/sst_frontend.cpp"
    fi

    # II. Modify Frontend CMakeLists.txt
    FRONTEND_CMAKE="${RAM2_SRC}/src/ramulator/frontend/CMakeLists.txt"
    if [ -f "$FRONTEND_CMAKE" ] && ! grep -q "impl/external_wrapper/sst_frontend.cpp" "$FRONTEND_CMAKE"; then
        sed -i '/impl\/external.cpp/a \    impl/external_wrapper/sst_frontend.cpp' "$FRONTEND_CMAKE"
    fi

    # III. Copy sedram.py
    PYTHON_DRAM_DIR="${RAM2_SRC}/python/ramulator/dram"
    mkdir -p "$PYTHON_DRAM_DIR"
    if [ -f "${PROJECT_DIR}/patchfiles/sedram.py" ]; then
        cp "${PROJECT_DIR}/patchfiles/sedram.py" "${PYTHON_DRAM_DIR}/sedram.py"
    fi

    # IV. Modify DRAM CMakeLists.txt
    DRAM_CMAKE="${RAM2_SRC}/src/ramulator/dram/CMakeLists.txt"
    if [ -f "$DRAM_CMAKE" ] && ! grep -q "impl/SeDRAM.cpp" "$DRAM_CMAKE"; then
        sed -i '/commands\/populate.h/a \    impl/SeDRAM.cpp' "$DRAM_CMAKE"
    fi

    # V. Update refresh scope array in all_bank.cpp
    ALL_BANK_CPP="${RAM2_SRC}/src/ramulator/controller/refresh/impl/all_bank.cpp"
    if [ -f "$ALL_BANK_CPP" ] && ! grep -q '"SeDRAM", "BankGroup"' "$ALL_BANK_CPP"; then
        sed -i 's/std::array<std::pair<std::string_view, std::string_view>, 11>/std::array<std::pair<std::string_view, std::string_view>, 12>/g' "$ALL_BANK_CPP"
        sed -i '/{"HBM4", "PseudoChannel"},/a \    {"SeDRAM", "BankGroup"},' "$ALL_BANK_CPP"
    fi
fi

# Build Ramulator 2
echo "[+] Building Ramulator 2..."
mkdir -p "${WORKSPACE_DIR}/ramulator2/build"
pushd "${WORKSPACE_DIR}/ramulator2/build" > /dev/null
cmake ..
make -j"$(nproc)"
popd > /dev/null

# Install Python interface
echo "[+] Installing Ramulator 2 Python package..."
pip install -e "${WORKSPACE_DIR}/ramulator2"

# ==============================================================================
# Part 2: SST-Core Build & Install
# ==============================================================================
echo "========================================================================"
echo " Part 2: Building SST-Core"
echo "========================================================================"

SST_CORE_DIR="${WORKSPACE_DIR}/sst-core"
SST_CORE_INSTALL="${SST_CORE_DIR}/sst-core-install"

if [ -d "$SST_CORE_DIR" ]; then
    pushd "$SST_CORE_DIR" > /dev/null
    
    echo "[+] Bootstrapping SST-Core..."
    ./autogen.sh
    
    mkdir -p build && cd build
    echo "[+] Configuring SST-Core..."
    ../configure --prefix="${SST_CORE_INSTALL}"
    
    echo "[+] Compiling and Installing SST-Core..."
    make -j"$(nproc)" install
    
    # Export PATH dynamically for subsequent steps in this session
    export PATH="${SST_CORE_INSTALL}/bin:$PATH"
    
    popd > /dev/null
else
    echo "[!] Directory $SST_CORE_DIR not found. Skipping SST-Core build."
fi

# ==============================================================================
# Part 3: SST-Elements Patch & Selective Build
# ==============================================================================
echo "========================================================================"
echo " Part 3: Patching & Building SST-Elements"
echo "========================================================================"

SST_ELEMS_DIR="${WORKSPACE_DIR}/sst-elements"
PATCH_FILE="${PROJECT_DIR}/patchfiles/patch_sst-elements.patch"

if [ -d "$SST_ELEMS_DIR" ]; then
    pushd "$SST_ELEMS_DIR" > /dev/null
    
    echo "[+] Bootstrapping SST-Elements..."
    ./autogen.sh
    
    if [ -f "$PATCH_FILE" ]; then
        echo "[+] Applying SST-Elements patch file..."
        patch -p1 --ignore-whitespace < "$PATCH_FILE"
    else
        echo "[!] Patch file $PATCH_FILE not found. Skipping patch stage."
    fi
    
    popd > /dev/null
else
    echo "[!] Directory $SST_ELEMS_DIR not found. Skipping SST-Elements stage."
fi

# Run selective build script
ELEMS_BUILD_SCRIPT="${PROJECT_DIR}/scripts/build_sst-elements.sh"
if [ -f "$ELEMS_BUILD_SCRIPT" ]; then
    echo "[+] Executing selective SST-Elements build script..."
    chmod +x "$ELEMS_BUILD_SCRIPT"
    "$ELEMS_BUILD_SCRIPT"
else
    echo "[!] Build script $ELEMS_BUILD_SCRIPT not found."
fi

echo "========================================================================"
echo " Setup Completed Successfully inside $(pwd)!"
echo "========================================================================"