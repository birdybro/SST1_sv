#!/usr/bin/env bash
# Basic synthesis sanity check for RTL.
#
# Uses Yosys to read all RTL and run a generic elaboration + synth flow.
# This is not a full timing-closed flow; it is a quick check that the RTL
# is synthesizable (no unsupported constructs, no missing references,
# no obvious latches/blackboxes).
#
# Exits 0 on success. Exits non-zero on Yosys failure. Exits 2 if Yosys
# is not installed.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
RTL_DIR="${ROOT_DIR}/rtl"
BUILD_DIR="${ROOT_DIR}/sim/build"

if [ ! -d "${RTL_DIR}" ]; then
    echo "synth_check: no rtl/ directory found; nothing to check."
    exit 0
fi

# Compile only .sv files; .svh headers live on the include path.
mapfile -t RTL_FILES < <(find "${RTL_DIR}" -type f -name '*.sv' | sort)

if [ "${#RTL_FILES[@]}" -eq 0 ]; then
    echo "synth_check: no SystemVerilog files under rtl/; nothing to check."
    exit 0
fi

if ! command -v yosys >/dev/null 2>&1; then
    cat >&2 <<'EOF'
synth_check: yosys not found.

Install Yosys from https://yosyshq.net/yosys/ (apt: yosys) then re-run
scripts/synth_check.sh.

If you are on Windows and have Yosys installed inside WSL, run this
script from inside WSL, e.g.:
    wsl bash -c 'cd /mnt/c/path/to/SST1_sv && ./scripts/synth_check.sh'
EOF
    exit 2
fi

mkdir -p "${BUILD_DIR}"

# Build a Yosys script. read_verilog -sv is used because Yosys' SystemVerilog
# support is partial; some constructs may require -DSYNTHESIS guarding inside
# the RTL. The top module is left implicit so Yosys picks the highest in the
# hierarchy. Once sst1_core.sv exists, this can be tightened to -top sst1_core.
SCRIPT="${BUILD_DIR}/synth_check.ys"
{
    for f in "${RTL_FILES[@]}"; do
        printf 'read_verilog -sv -I %q %q\n' "${RTL_DIR}/common" "${f}"
    done
    echo "hierarchy -check"
    echo "proc"
    echo "opt"
    echo "check -assert"
} > "${SCRIPT}"

echo "synth_check: running yosys (script: ${SCRIPT})"
yosys -q -s "${SCRIPT}"
echo "synth_check: OK"
