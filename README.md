# SST1_sv

A synthesizable SystemVerilog reimplementation of the 3dfx Voodoo Graphics
(SST-1) architecture, intended for FPGA experimentation and educational use.

## Scope

This project incrementally builds a register-compatible and
behavior-compatible Voodoo 1-style graphics pipeline in synthesizable
SystemVerilog. The implementation is structured as independently testable
modules covering:

- Host/MMIO bus interface and address decoding
- SST-1 memory-mapped register file
- Command FIFO and command decoder
- Triangle setup and rasterization
- Color, depth, texture, and fog pipelines
- Linear frame-buffer (LFB) access path
- Frame-buffer memory abstraction
- Video scanout

A clean internal MMIO bus is used for early development. A real PCI front
end may be added later as a wrapper.

## Non-goals

This project is **not**:

- **Transistor-accurate.** No attempt is made to reproduce the original
  ASIC's internal microarchitecture, gate-level timing, or analog
  characteristics.
- **Cycle-accurate to the original ASIC.** Pipeline depths and per-stage
  latencies are chosen for FPGA-friendly implementation.
- **A drop-in replacement for the original Voodoo board.** Bus interfaces,
  memory interfaces, and video output are reworked for modern FPGA targets.
- **A general-purpose 3D accelerator.** Only the documented SST-1 feature
  set is in scope.

Where exact behavior is unknown from public documentation, the code is
marked with `// TODO-COMPAT:` and verified against MAME/PCem behavior over
time. Where behavior is intentionally simplified, the code is marked
`// APPROXIMATION:`.

## References

See `docs/references.md` for the primary source documents (SST-1 spec,
MAME, PCem, and prior FPGA work) used as architectural references.

## Repository layout

```
.
├── README.md                Project overview (this file)
├── tasks.md                 Phased task tracker
├── docs/                    Architecture, registers, fixed-point, refs
├── rtl/                     Synthesizable SystemVerilog RTL
│   ├── common/              Shared packages, helpers
│   ├── pci/                 (Optional) PCI front-end wrapper
│   ├── regs/                Register file
│   ├── fifo/                Command and generic FIFOs
│   ├── raster/              Triangle setup, rasterizer, interpolators
│   ├── texture/             Texture memory and sampling
│   ├── framebuffer/         Frame-buffer memory and LFB path
│   ├── video/               Scanout and pixel-stream output
│   └── top/                 Top-level core integration
├── sim/                     Simulation collateral
│   ├── tb/                  SystemVerilog testbenches
│   ├── models/              Behavioral / reference models
│   └── vectors/             Golden vectors and test inputs
├── scripts/                 lint, test, synth_check entry points
└── formal/                  Optional formal-verification harnesses
```

## Build and test

Tooling assumptions are open-source-first. Each script fails with
installation guidance if its tool is not available.

- `./scripts/lint.sh` — RTL lint pass (Verilator or Verible if installed)
- `./scripts/test.sh` — Run available SystemVerilog testbenches
- `./scripts/synth_check.sh` — Basic synthesis sanity check (Yosys)

On Windows, these scripts can be run from Git Bash, WSL, or any POSIX-like
shell. Native PowerShell equivalents may be added later.

## License

MIT. See `LICENSE`.

Reference documents and external projects retain their own licenses; this
project uses them as architectural and behavioral references only and does
not copy their code verbatim.
