#!/usr/bin/env bash

# ------------------------------------------------------------------------------
# Universal Build Script for RISC-V Bare-Metal Workloads (Graph, Sparse, etc.)
# ------------------------------------------------------------------------------
WORKLOADS_DIR="workloads"
DEFAULT_SRC="graph.c"
DEFAULT_OUT="workload.elf"
COMPILER="riscv64-unknown-elf-gcc"

OPTIMIZATION="-O2"
MARCH="rv64im"         
MABI="lp64"           
MULTICORE_MODE=false
NUM_CORES=4           

# Memory Map Configuration
# Fixed VMA overlap by pushing RAM_BASE from 1MB (0x00100000) to 16MB (0x01000000)
FLASH_BASE="0x00010000"
RAM_BASE="0x01000000"    
REGION_SIZE="0x04000000" # Reserved 64 MB region size
STACK_SIZE="0x00100000"  # Reserved 1 MB stack

EXPLICIT_SRC=""
EXPLICIT_OUT=""

show_help() {
    cat << EOF
Usage: $(basename "$0") [OPTIONS] [source_file.c] [output_file.elf]

Options:
  --multicore [CORES]   Enable multicore target mode.
  -o, --output FILE     Set destination output ELF file explicitly. Default: $WORKLOADS_DIR/$DEFAULT_OUT
  -O, --opt LEVEL       Set optimization level (e.g., -O0, -O2). Default: $OPTIMIZATION
  -m, --march ARCH      Set target architecture string. Default: $MARCH
  -a, --mabi ABI        Set target ABI. Default: $MABI
  -h, --help            Show this help message and exit
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help)
            show_help
            exit 0
            ;;
        --multicore)
            MULTICORE_MODE=true
            if [[ "$2" =~ ^[0-9]+$ ]]; then
                NUM_CORES="$2"
                shift 2
            else
                shift 1
            fi
            ;;
        -o|--output)
            EXPLICIT_OUT="$2"
            shift 2
            ;;
        -O)
            OPTIMIZATION="-O$2"
            shift 2
            ;;
        -O*)
            OPTIMIZATION="$1"
            shift 1
            ;;
        -m|--march)
            MARCH="$2"
            shift 2
            ;;
        -a|--mabi)
            MABI="$2"
            shift 2
            ;;
        -*)
            echo "Error: Unknown option '$1'" >&2
            show_help
            exit 1
            ;;
        *)
            if [ -z "$EXPLICIT_SRC" ]; then
                EXPLICIT_SRC="$1"
            elif [ -z "$EXPLICIT_OUT" ]; then
                EXPLICIT_OUT="$1"
            fi
            shift 1
            ;;
    esac
done

# Resolve paths: prefix WORKLOADS_DIR unless the path is absolute or explicitly specifies a directory
RAW_SRC="${EXPLICIT_SRC:-$DEFAULT_SRC}"
if [[ "$RAW_SRC" == /* ]] || [[ "$RAW_SRC" == *"/"* ]]; then
    SRC_FILE="$RAW_SRC"
else
    SRC_FILE="${WORKLOADS_DIR}/${RAW_SRC}"
fi

RAW_OUT="${EXPLICIT_OUT:-$DEFAULT_OUT}"
if [[ "$RAW_OUT" == /* ]] || [[ "$RAW_OUT" == *"/"* ]]; then
    OUT_FILE="$RAW_OUT"
else
    OUT_FILE="${WORKLOADS_DIR}/${RAW_OUT}"
fi

if ! command -v "$COMPILER" &> /dev/null; then
    echo "Error: Toolchain binary '$COMPILER' could not be found in your PATH." >&2
    exit 1
fi

if [ ! -f "$SRC_FILE" ]; then
    echo "Error: Input source file '$SRC_FILE' does not exist." >&2
    exit 1
fi

# Ensure output target directory exists automatically
OUT_DIR=$(dirname "$OUT_FILE")
if [ ! -d "$OUT_DIR" ]; then
    mkdir -p "$OUT_DIR"
fi

echo "=========================================================================="
echo "Compiling RISC-V Bare-Metal Workload ($SRC_FILE) for SST"
echo "=========================================================================="
echo "Compiler:    $COMPILER"
echo "Target:      $OUT_FILE"
echo "Arch/ABI:    -march=$MARCH -mabi=$MABI"
echo "Opt Level:   $OPTIMIZATION"
echo "Flash Base:  $FLASH_BASE"
echo "RAM Base:    $RAM_BASE (Size: $REGION_SIZE / 64MB)"
echo "Stack Size:  $STACK_SIZE (1MB)"
echo "--------------------------------------------------------------------------"

EXTRA_FLAGS=()
if [ "$MULTICORE_MODE" = true ]; then
    EXTRA_FLAGS+=(
        "-DCONFIG_MULTICORE"
        "-DNUM_CORES=$NUM_CORES"
    )
fi

"$COMPILER" "$OPTIMIZATION" \
  -march="$MARCH" \
  -mabi="$MABI" \
  -mcmodel=medany \
  -ffreestanding \
  --specs=picolibc.specs \
  -nostartfiles \
  -static \
  "${EXTRA_FLAGS[@]}" \
  -Wl,--defsym=__flash="$FLASH_BASE" \
  -Wl,--defsym=__flash_size="$REGION_SIZE" \
  -Wl,--defsym=__ram="$RAM_BASE" \
  -Wl,--defsym=__ram_size="$REGION_SIZE" \
  -Wl,--defsym=__stack_size="$STACK_SIZE" \
  -Wl,-e,_start \
  "$SRC_FILE" \
  -lm \
  -o "$OUT_FILE"

if [ $? -eq 0 ]; then
    echo "Success! Binary generated cleanly at: $OUT_FILE"
    if command -v riscv64-unknown-elf-size &> /dev/null; then
        echo ""
        echo "Executable Memory Footprint Summary:"
        riscv64-unknown-elf-size "$OUT_FILE"
    fi
    echo "=========================================================================="
else
    echo "Error: Compilation failed." >&2
    exit 2
fi