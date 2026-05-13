#!/usr/bin/env bash
# Lint all SystemVerilog RTL under rtl/.
#
# Tool preference:
#   1. Verilator (verilator --lint-only)
#   2. Verible   (verible-verilog-lint)
#
# Exits 0 on success or if no RTL exists yet. Exits non-zero on lint
# failure. Exits 2 if no supported linter is installed (with guidance).

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
RTL_DIR="${ROOT_DIR}/rtl"

# Collect .sv / .svh files (newline-separated; safe because we control paths).
if [ ! -d "${RTL_DIR}" ]; then
    echo "lint: no rtl/ directory found; nothing to lint."
    exit 0
fi

mapfile -t SV_FILES < <(find "${RTL_DIR}" -type f \( -name '*.sv' -o -name '*.svh' \) | sort)

if [ "${#SV_FILES[@]}" -eq 0 ]; then
    echo "lint: no SystemVerilog files found under rtl/; nothing to lint."
    exit 0
fi

if command -v verilator >/dev/null 2>&1; then
    echo "lint: using verilator --lint-only"
    # -Wall is noisy on early scaffolding; start with default warnings and
    # tighten in later phases.
    verilator --lint-only -sv \
        -I"${RTL_DIR}/common" \
        "${SV_FILES[@]}"
    echo "lint: OK (verilator)"
    exit 0
fi

if command -v verible-verilog-lint >/dev/null 2>&1; then
    echo "lint: using verible-verilog-lint"
    verible-verilog-lint "${SV_FILES[@]}"
    echo "lint: OK (verible)"
    exit 0
fi

cat >&2 <<'EOF'
lint: no supported linter found.

Install one of:
  - Verilator   https://verilator.org/      (apt: verilator)
  - Verible     https://github.com/chipsalliance/verible

Then re-run scripts/lint.sh.
EOF
exit 2
