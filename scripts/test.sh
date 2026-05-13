#!/usr/bin/env bash
# Run all available SystemVerilog testbenches under sim/tb/.
#
# Test discovery:
#   Any file named tb_*.sv under sim/tb/ is treated as a self-checking
#   testbench. RTL sources under rtl/ are passed as additional sources.
#
# Tool preference:
#   1. Verilator (compile + run binary)
#   2. Icarus Verilog (iverilog + vvp)
#
# Exits 0 if all tests pass or no tests exist yet. Exits non-zero on any
# test failure. Exits 2 if no supported simulator is installed.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
RTL_DIR="${ROOT_DIR}/rtl"
TB_DIR="${ROOT_DIR}/sim/tb"
BUILD_DIR="${ROOT_DIR}/sim/build"

if [ ! -d "${TB_DIR}" ]; then
    echo "test: no sim/tb/ directory found; nothing to test."
    exit 0
fi

mapfile -t TB_FILES < <(find "${TB_DIR}" -type f -name 'tb_*.sv' | sort)

if [ "${#TB_FILES[@]}" -eq 0 ]; then
    echo "test: no testbenches (tb_*.sv) found; nothing to test."
    exit 0
fi

mapfile -t RTL_FILES < <(find "${RTL_DIR}" -type f \( -name '*.sv' -o -name '*.svh' \) 2>/dev/null | sort || true)

mkdir -p "${BUILD_DIR}"

run_with_verilator() {
    local tb="$1"
    local name
    name="$(basename "${tb}" .sv)"
    local obj_dir="${BUILD_DIR}/${name}.verilator"
    echo "test: building ${name} with verilator"
    verilator --binary -sv \
        -Wno-fatal \
        -I"${RTL_DIR}/common" \
        --Mdir "${obj_dir}" \
        --top-module "${name}" \
        "${RTL_FILES[@]}" "${tb}"
    echo "test: running ${name}"
    "${obj_dir}/V${name}"
}

run_with_iverilog() {
    local tb="$1"
    local name
    name="$(basename "${tb}" .sv)"
    local out="${BUILD_DIR}/${name}.vvp"
    echo "test: building ${name} with iverilog"
    iverilog -g2012 \
        -I "${RTL_DIR}/common" \
        -o "${out}" \
        "${RTL_FILES[@]}" "${tb}"
    echo "test: running ${name}"
    vvp "${out}"
}

if command -v verilator >/dev/null 2>&1; then
    SIM=verilator
elif command -v iverilog >/dev/null 2>&1 && command -v vvp >/dev/null 2>&1; then
    SIM=iverilog
else
    cat >&2 <<'EOF'
test: no supported simulator found.

Install one of:
  - Verilator       https://verilator.org/      (apt: verilator)
  - Icarus Verilog  https://steveicarus.github.io/iverilog/

Then re-run scripts/test.sh.
EOF
    exit 2
fi

echo "test: simulator = ${SIM}"

fail=0
for tb in "${TB_FILES[@]}"; do
    case "${SIM}" in
        verilator) run_with_verilator "${tb}" || fail=1 ;;
        iverilog)  run_with_iverilog  "${tb}" || fail=1 ;;
    esac
done

if [ "${fail}" -ne 0 ]; then
    echo "test: FAILED"
    exit 1
fi

echo "test: OK"
