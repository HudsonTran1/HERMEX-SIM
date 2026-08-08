#!/usr/bin/env bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

COMPILER="${COMPILER:-riscv64-linux-gnu-gcc}"
SRC_FILE="${1:-./workload_files/old/working_single_and_multi/multicore_test.c}"
OUT_FILE="${2:-./workload_files/elf/workload2.elf}"

ENTRY_STUB="${SCRIPT_DIR}/entry.s"
LINKER_SCRIPT="${SCRIPT_DIR}/vanadis.ld"

echo "Building RISC-V binary: ${OUT_FILE}..."

"$COMPILER" -O2 \
  -march=rv64imafd \
  -mabi=lp64d \
  -mcmodel=medany \
  -static \
  -nostdlib \
  -nostartfiles \
  -ffreestanding \
  -fno-stack-protector \
  -fno-builtin \
  -T "$LINKER_SCRIPT" \
  -Wl,--gc-sections \
  "$ENTRY_STUB" \
  "$SRC_FILE" \
  -o "$OUT_FILE"

echo "ELF Entry point: $(riscv64-linux-gnu-readelf -h "$OUT_FILE" | awk '/Entry point/ {print $4}')"
echo "Build complete -> ${OUT_FILE}"