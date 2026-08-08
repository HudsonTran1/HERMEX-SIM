#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# SST-Elements Selective Build Script
# Supports CLI flags, environment variables, or defaults.
# ==============================================================================

DEFAULT_BASE_DIR="/workspace"

show_help() {
    cat << EOF
Usage: $(basename "$0") [OPTIONS]

Selective build script for SST-Elements (memHierarchy, vanadis, mmu) with Ramulator 2 support.

Options:
  -h, --help                Show this help message and exit
  -b, --base-dir DIR        Set base working directory (default: $DEFAULT_BASE_DIR)
  -i, --install-dir DIR     SST install prefix path (default: <BASE_DIR>/sst-install)
  -c, --core-dir DIR        SST Core path (default: <INSTALL_DIR>)
  -r, --ramulator-dir DIR   Ramulator 2 path (default: <BASE_DIR>/ramulator2)
  -e, --elements-dir DIR    SST Elements repository path (default: <BASE_DIR>/sst-elements)
  -j, --jobs N              Number of parallel build jobs (default: nproc)
  -d, --debug               Build with debug symbols (-g -O0), verbose logging
                             (-DVANADIS_BUILD_DEBUG) & general debug macros
                             (-DDEBUG -DSST_DEBUG) for GDB & trace output

Component Selectors (If none are specified, all components will be built):
  -v, --vanadis             Only build/recompile the vanadis component
  -m, --mmu                 Only build/recompile the mmu component
  --mem, --memhierarchy     Only build/recompile the memHierarchy component

Examples:
  # Recompile all selected components in DEBUG mode:
  ./$(basename "$0") -d

  # Only recompile vanadis and mmu with debug symbols:
  ./$(basename "$0") -v -m -d -j 8
EOF
    exit 0
}

# Parse Command-Line Options
CLI_BASE_DIR=""
CLI_INSTALL_DIR=""
CLI_CORE_DIR=""
CLI_RAMULATOR_DIR=""
CLI_ELEMENTS_DIR=""
CLI_JOBS=""
BUILD_DEBUG=0

# Component selection flags (0 = false, 1 = true)
BUILD_VANADIS=0
BUILD_MMU=0
BUILD_MEMHIERARCHY=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help)
            show_help
            ;;
        -b|--base-dir)
            CLI_BASE_DIR="$2"
            shift 2
            ;;
        -i|--install-dir)
            CLI_INSTALL_DIR="$2"
            shift 2
            ;;
        -c|--core-dir)
            CLI_CORE_DIR="$2"
            shift 2
            ;;
        -r|--ramulator-dir)
            CLI_RAMULATOR_DIR="$2"
            shift 2
            ;;
        -e|--elements-dir)
            CLI_ELEMENTS_DIR="$2"
            shift 2
            ;;
        -j|--jobs)
            CLI_JOBS="$2"
            shift 2
            ;;
        -d|--debug)
            BUILD_DEBUG=1
            shift 1
            ;;
        -v|--vanadis)
            BUILD_VANADIS=1
            shift 1
            ;;
        -m|--mmu)
            BUILD_MMU=1
            shift 1
            ;;
        --mem|--memhierarchy)
            BUILD_MEMHIERARCHY=1
            shift 1
            ;;
        *)
            echo "Error: Unknown option '$1'"
            echo "Use '$(basename "$0") --help' for usage instructions."
            exit 1
            ;;
    esac
done

# Resolve Final Paths
BASE_DIR="${CLI_BASE_DIR:-${BASE_DIR:-$DEFAULT_BASE_DIR}}"
SST_INSTALL_DIR="${CLI_INSTALL_DIR:-${SST_INSTALL_DIR:-$BASE_DIR/sst-install}}"
SST_CORE_DIR="${CLI_CORE_DIR:-${SST_CORE_DIR:-$SST_INSTALL_DIR}}"
RAMULATOR2_DIR="${CLI_RAMULATOR_DIR:-${RAMULATOR2_DIR:-$BASE_DIR/ramulator2}}"
SST_ELEMENTS_DIR="${CLI_ELEMENTS_DIR:-${SST_ELEMENTS_DIR:-$BASE_DIR/sst-elements}}"
JOBS="${CLI_JOBS:-${JOBS:-$(nproc)}}"

# If no specific target was selected, default to building all of them
if [ $BUILD_VANADIS -eq 0 ] && [ $BUILD_MMU -eq 0 ] && [ $BUILD_MEMHIERARCHY -eq 0 ]; then
    BUILD_VANADIS=1
    BUILD_MMU=1
    BUILD_MEMHIERARCHY=1
fi

# Build Flags Configuration
EXTRA_FLAGS=""
if [ $BUILD_DEBUG -eq 1 ]; then
    echo ">> DEBUG MODE ACTIVATED (-g -O0, verbose tracing enabled) <<"
    EXTRA_FLAGS="-g -O0 -DDEBUG -DSST_DEBUG -DVANADIS_BUILD_DEBUG"
fi

echo "================================================="
echo " SST-Elements Custom Selective Build"
echo "================================================="
echo " Install Prefix : $SST_INSTALL_DIR"
echo " SST-Core Path  : $SST_CORE_DIR"
echo " Ramulator2 Path: $RAMULATOR2_DIR"
echo " Elements Path  : $SST_ELEMENTS_DIR"
echo " Debug Build    : $( [ $BUILD_DEBUG -eq 1 ] && echo 'YES' || echo 'NO' )"
echo " Build Cores    : $JOBS"
echo "-------------------------------------------------"
echo " Building Targets:"
[ $BUILD_MEMHIERARCHY -eq 1 ] && echo "  -> memHierarchy"
[ $BUILD_VANADIS -eq 1 ]      && echo "  -> vanadis"
[ $BUILD_MMU -eq 1 ]          && echo "  -> mmu"
echo "================================================="

# Pre-flight checks
if [ ! -d "$SST_ELEMENTS_DIR" ]; then
    echo "Error: SST Elements directory not found at: $SST_ELEMENTS_DIR"
    exit 1
fi

if [ ! -d "$RAMULATOR2_DIR" ]; then
    echo "Error: Ramulator 2 directory not found at: $RAMULATOR2_DIR"
    exit 1
fi

# Define Ramulator 2 & Debug include/link flags
RAMULATOR_CPPFLAGS="-I${RAMULATOR2_DIR}/src -I${RAMULATOR2_DIR}/src/ramulator $EXTRA_FLAGS"
RAMULATOR_CXXFLAGS="$EXTRA_FLAGS"
RAMULATOR_LDFLAGS="-L${RAMULATOR2_DIR} -Wl,-rpath,${RAMULATOR2_DIR}"

# 1. Configure SST-Elements Root
echo "--> Running configure in $SST_ELEMENTS_DIR..."
cd "$SST_ELEMENTS_DIR"

./configure \
    --prefix="$SST_INSTALL_DIR" \
    --with-sst-core="$SST_CORE_DIR" \
    --with-ramulator2="$RAMULATOR2_DIR" \
    CPPFLAGS="$RAMULATOR_CPPFLAGS" \
    CXXFLAGS="$RAMULATOR_CXXFLAGS" \
    LDFLAGS="$RAMULATOR_LDFLAGS"

# Selective Build Helper Function
build_and_register_element() {
    local elem="$1"
    echo "================================================="
    echo " Selective Rebuild: $elem"
    echo "================================================="
    
    # Clean, compile, and install ONLY the targeted element from the root Makefile context
    make -C "src/sst/elements/$elem" clean || true
    make -C "src/sst/elements/$elem" -j"$JOBS" \
        CPPFLAGS="$RAMULATOR_CPPFLAGS" \
        CXXFLAGS="$RAMULATOR_CXXFLAGS" \
        LDFLAGS="$RAMULATOR_LDFLAGS"
    make -C "src/sst/elements/$elem" install

    # Explicitly register with SST Core to prevent missing subcomponent errors
    echo "--> Registering $elem with SST Core..."
    "$SST_INSTALL_DIR/bin/sst-register" SST_ELEMENT_SOURCE "${elem}=${SST_ELEMENTS_DIR}/src/sst/elements/${elem}" || true
}

# 2. Build Target Elements based on selection
if [ $BUILD_MEMHIERARCHY -eq 1 ]; then
    build_and_register_element "memHierarchy"
fi

if [ $BUILD_VANADIS -eq 1 ]; then
    build_and_register_element "vanadis"
fi

if [ $BUILD_MMU -eq 1 ]; then
    build_and_register_element "mmu"
fi

echo "================================================="
echo " Selective Build Complete!"
echo " Installed libraries to: $SST_INSTALL_DIR/lib/sst-elements-library/"
echo "================================================="