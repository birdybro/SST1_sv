# Tasks

Progress is tracked phase-by-phase. One major task per commit. Each task
should leave the repo in a state where `scripts/lint.sh`, `scripts/test.sh`,
and `scripts/synth_check.sh` either pass or fail with clear, expected
guidance about missing tooling.

## Phase 0 — Project foundation
- [x] Create repository structure.
- [x] Add README with scope, non-goals, references, and build instructions.
- [x] Add docs/references.md with links to SST-1 spec, MAME, PCem, and FPGA reference projects.
- [x] Add scripts/lint.sh, scripts/test.sh, and scripts/synth_check.sh.
- [x] Add basic CI-friendly command assumptions using available open-source tools where possible.
- [x] Commit and push.

## Phase 1 — Architectural documentation
- [x] Summarize SST-1 top-level architecture in docs/architecture.md.
- [x] Identify major blocks: host/PCI interface, register file, command FIFO, rasterizer, texture unit, frame buffer interface, video output.
- [x] Document what will be modeled accurately first and what will be approximated initially.
- [x] Commit and push.

  Notes:
  - Architecture doc now contains an ASCII block diagram, per-block
    descriptions, clocking/reset strategy, memory partitioning, accuracy
    roadmap (accurate-first vs approximated-first vs deferred), and a
    seeded open-questions section pointing at MAME/PCem cross-checks.
  - MMIO bus signal table is the working baseline that Phase 3 will turn
    into an actual interface module.

## Phase 2 — Register map skeleton
- [x] Create a synthesizable register-file module for the SST-1 memory-mapped register region.
- [x] Define register addresses from the SST-1 spec in a SystemVerilog package.
- [x] Implement readable/writable control registers with reset defaults.
- [x] Add testbench for register writes, reads, masking, and reset behavior.
- [x] Commit and push.

  Notes:
  - `rtl/common/sst1_consts.svh` collects byte offsets for the SST-1
    register region (Phase 2 subset), plus bus-geometry, BAR-window, and
    fbiInit reset-default constants. V2+/Banshee-only registers (intrCtrl,
    fbiInit5..7, s-setup block, chromaRange, userIntrCMD, BLT engine) are
    intentionally omitted.
  - Originally written as a SystemVerilog `package` with `import sst1_pkg::*;`,
    but Yosys 0.33's vanilla `read_verilog -sv` does not parse the `::`
    package-scope token (TOK_PACKAGESEP error). Converted to a bare
    `localparam` header `\`included` inside each consumer's module body so
    its constants land in module scope. No include guard — each module
    declares them in its own scope. Once the project adopts a Yosys with
    the slang plugin (or moves to a newer Yosys with full SV-package
    support), this can become a proper `package` again.
  - `rtl/regs/sst1_regs.sv` implements RW mode registers (fbzMode,
    fbzColorPath, alphaMode, fogMode, lfbMode, clipLeftRight, clipLowYHighY,
    stipple, color0/1), the fbiInit0..4 + back_porch + video_dims RW block,
    write-only storage for fog/za/chroma_key and triangle parameter shadow
    (0x008..0x07C), the TMU register block (0x300..0x320), and single-cycle
    command pulses for triangleCMD / ftriangleCMD / nopCMD / fastfillCMD /
    swapbufferCMD. Reads from reserved or write-only offsets return 0.
    `bus_ready` is tied high in Phase 2; FIFO back-pressure for command
    triggers is added in Phase 4. Port widths are hardcoded literals
    (24/32/4) so the port list does not depend on package symbols.
  - The byte-enable masking helper is written in Verilog-2001 function form
    (input declarations + name-as-return, no `return` statement); SV-style
    `function ... return expr;` triggered a Yosys parse error.
  - `sim/tb/tb_sst1_regs.sv` is self-checking: covers fbiInit0..4 reset
    values, RW round-trip, byte-enable masking, write-only behavior,
    reserved-offset reads, all five command pulses, and a re-reset cycle.
    30 checks, 0 failures under Verilator 5.048.
  - fbiInit0..4 reset values follow MAME's chosen defaults; the public spec
    does not publish silicon defaults (marked `// TODO-COMPAT:` in RTL).
  - Scripts ship a "tool not found, but try WSL" fallback message because
    the dev host on Windows runs Verilator/Yosys via WSL. Both lint.sh
    (Verilator 5.048 --lint-only) and synth_check.sh (Yosys 0.33) pass
    cleanly via `wsl bash -c './scripts/lint.sh'` etc.
  - Scripts now compile only `.sv` files; `.svh` headers live on the
    include path (`-I rtl/common`) because passing a header as a top-level
    source would try to compile its bare declarations at file scope.

## Phase 3 — Host bus abstraction
- [ ] Implement a simple internal host/MMIO bus interface independent of real PCI.
- [ ] Add address decode for register space, linear frame buffer space, and texture memory space.
- [ ] Add bus response/stall/error signals.
- [ ] Add tests for address decoding.
- [ ] Commit and push.

## Phase 4 — Command FIFO
- [ ] Implement synthesizable parameterized FIFO.
- [ ] Add command FIFO for triangle, fastfill, swapbuffer, and nop commands.
- [ ] Model FIFO full/empty behavior at the host-visible boundary.
- [ ] Add tests for FIFO ordering, overflow protection, and backpressure.
- [ ] Commit and push.

## Phase 5 — Fixed-point math foundation
- [ ] Document fixed-point formats in docs/fixed_point.md.
- [ ] Implement reusable signed/unsigned fixed-point helpers where synthesizable.
- [ ] Add modules/functions for add, subtract, compare, saturate, clamp, and arithmetic shift.
- [ ] Add tests for edge cases and rounding behavior.
- [ ] Commit and push.

## Phase 6 — Frame buffer memory model
- [ ] Implement parameterized frame buffer memory interface.
- [ ] Support color buffer and depth buffer storage.
- [ ] Support simple single-clock BRAM-friendly memory first.
- [ ] Add abstraction layer for future SDRAM/DDR integration.
- [ ] Add tests for reads, writes, byte enables, and address mapping.
- [ ] Commit and push.

## Phase 7 — Linear frame buffer path
- [ ] Implement LFB write path according to SST-1 register behavior where practical.
- [ ] Implement basic LFB read path.
- [ ] Add format conversion/masking as documented.
- [ ] Add tests using small frame buffer dimensions.
- [ ] Commit and push.

## Phase 8 — Triangle setup ingestion
- [ ] Implement capture of triangle setup registers: vertex coordinates, color starts/deltas, Z, S, T, W, and command trigger.
- [ ] Support integer and floating-style register paths only after documenting the intended behavior.
- [ ] Start with fixed-point internal representation.
- [ ] Add tests that a triangle command snapshots the expected state.
- [ ] Commit and push.

## Phase 9 — Basic rasterizer
- [ ] Implement a simple edge-function or scanline triangle rasterizer.
- [ ] Generate pixel coordinates inside a triangle.
- [ ] Respect clipping registers.
- [ ] Start with flat color output.
- [ ] Add tests for simple triangles, degenerate triangles, clipping, and bounds.
- [ ] Commit and push.

## Phase 10 — Color interpolation
- [ ] Add Gouraud color interpolation using start and delta registers.
- [ ] Match documented fixed-point precision as closely as practical.
- [ ] Add saturation/clamping behavior.
- [ ] Add tests comparing expected interpolated colors.
- [ ] Commit and push.

## Phase 11 — Z-buffer path
- [ ] Implement Z interpolation.
- [ ] Implement depth compare functions from fbzMode.
- [ ] Implement conditional Z writes.
- [ ] Add tests for each depth function.
- [ ] Commit and push.

## Phase 12 — Color combine and alpha
- [ ] Implement a first-pass color combine path from fbzColorPath and alphaMode.
- [ ] Implement basic alpha test and alpha blending modes.
- [ ] Add tests for common blend modes.
- [ ] Commit and push.

## Phase 13 — Texture memory path
- [ ] Implement texture memory storage abstraction.
- [ ] Implement texture address calculation for basic 2D textures.
- [ ] Support nearest-neighbor sampling first.
- [ ] Add tests for texture load/read/sample addressing.
- [ ] Commit and push.

## Phase 14 — Perspective-correct texture coordinates
- [ ] Implement S, T, W interpolation.
- [ ] Add reciprocal or approximate reciprocal path for perspective correction.
- [ ] Document precision and approximation choices.
- [ ] Add tests against software-generated reference vectors.
- [ ] Commit and push.

## Phase 15 — Bilinear filtering and mip levels
- [ ] Implement bilinear filtering.
- [ ] Add mip level selection where practical.
- [ ] Add tests for filtering and texture edge/wrap behavior.
- [ ] Commit and push.

## Phase 16 — Fog, chroma key, dithering
- [ ] Implement fog color/table behavior initially as a documented approximation.
- [ ] Implement chroma key compare.
- [ ] Implement RGB dithering behavior.
- [ ] Add tests for each path.
- [ ] Commit and push.

## Phase 17 — Fast fill and buffer swap
- [ ] Implement fastfill command.
- [ ] Implement swapbuffer command at the architectural level.
- [ ] Add double-buffer state handling.
- [ ] Add tests for clear/fill/swap behavior.
- [ ] Commit and push.

## Phase 18 — Video output
- [ ] Implement scanout from frame buffer.
- [ ] Provide a generic RGB pixel-stream interface.
- [ ] Optionally add VGA or HDMI wrapper only after the core pixel stream is tested.
- [ ] Add testbench that scans a known frame.
- [ ] Commit and push.

## Phase 19 — Top-level integration
- [ ] Create top-level SST-1-style core wiring host bus, registers, command FIFO, rasterizer, texture, frame buffer, and video output.
- [ ] Add integration test that writes registers, issues a triangle command, and verifies frame-buffer pixels.
- [ ] Commit and push.

## Phase 20 — Compatibility validation
- [ ] Create software reference scripts that generate expected outputs for small test scenes.
- [ ] Compare RTL simulation output against reference images/pixel dumps.
- [ ] Add documented comparisons against MAME/PCem behavior where possible.
- [ ] Commit and push.

## Phase 21 — FPGA synthesis target
- [ ] Choose an initial FPGA target or keep target generic if board is unknown.
- [ ] Run synthesis check.
- [ ] Fix non-synthesizable constructs and timing-unfriendly structures.
- [ ] Document resource usage.
- [ ] Commit and push.

## Notes and discoveries

(Append phase-specific notes here as work progresses.)
