# Architecture

Top-level architectural overview of the SST-1 reimplementation in this
project. The goal is **register- and behavior-compatible** rendering of
the documented Voodoo Graphics feature set, on FPGA-friendly RTL. This
document is the design intent; the RTL is the source of truth.

Citations to the SST-1 spec Rev 1.61 and MAME/PCem are tracked at the
point of use (see `docs/references.md` for the attribution policy).

---

## 1. Top-level block diagram

```
                      ┌──────────────────────────────────────────┐
   host MMIO          │              sst1_core (top)             │
  (writes/reads) ───► │                                          │
                      │  ┌──────────────┐                        │
                      │  │ sst1_host_if │  internal MMIO bus     │
                      │  └──────┬───────┘  (addr, wdata, we,     │
                      │         │           be, rdata, ready)    │
                      │         ▼                                │
                      │  ┌──────────────┐                        │
                      │  │ sst1_addr_   │── reg / lfb / tex      │
                      │  │   decode     │   select strobes       │
                      │  └──┬───────┬───┘                        │
                      │     │       │                            │
                      │     ▼       ▼                            │
                      │ ┌──────┐ ┌──────────────┐                │
                      │ │ regs │ │ lfb / tex    │                │
                      │ │      │ │ port mux     │                │
                      │ └──┬───┘ └────┬─────────┘                │
                      │    │          │                          │
                      │    ▼          ▼                          │
                      │ ┌──────────────┐    ┌──────────────────┐ │
                      │ │ sst1_cmd_    │───►│ sst1_triangle_   │ │
                      │ │   fifo /     │    │   setup          │ │
                      │ │   decoder    │    └─────┬────────────┘ │
                      │ └──────────────┘          │              │
                      │                           ▼              │
                      │                  ┌──────────────────┐    │
                      │                  │ sst1_rasterizer  │    │
                      │                  └─────┬────────────┘    │
                      │   ┌────────────────────┼──────────────┐  │
                      │   ▼                    ▼              ▼  │
                      │ ┌──────────┐  ┌──────────────┐  ┌──────┐ │
                      │ │ sst1_    │  │ sst1_color_  │  │sst1_ │ │
                      │ │ interp / │  │   combine /  │  │zunit │ │
                      │ │ tex unit │  │   alpha /    │  │      │ │
                      │ │          │  │   fog/dither │  │      │ │
                      │ └────┬─────┘  └──────┬───────┘  └──┬───┘ │
                      │      │               │             │     │
                      │      └─────► ┌───────────────┐ ◄───┘     │
                      │              │ sst1_         │           │
                      │              │  framebuffer  │           │
                      │              └───────┬───────┘           │
                      │                      │                   │
                      │                      ▼                   │
                      │              ┌───────────────┐           │
                      │              │ sst1_video_   │── pixel   │
                      │              │   scanout     │   stream  │
                      │              └───────────────┘   out     │
                      └──────────────────────────────────────────┘
```

## 2. Blocks

### 2.1 Host interface (`sst1_host_if`, `sst1_addr_decode`)

A clean internal MMIO bus is the host-side interface during development.
A real PCI front end (`rtl/pci/`) is a Phase-21-or-later wrapper.

Bus signals (working baseline; finalized in Phase 3):

| Signal        | Dir | Width | Notes                                            |
|---------------|-----|-------|--------------------------------------------------|
| `addr`        | in  | 24    | Byte address into core MMIO region.              |
| `wdata`       | in  | 32    | Little-endian.                                   |
| `we`          | in  | 1     | Write strobe; valid with `addr`/`wdata`.         |
| `be`          | in  | 4     | Byte enables; mostly 4'b1111 for register space. |
| `re`          | in  | 1     | Read strobe.                                     |
| `rdata`       | out | 32    | Returned in same cycle when `ready=1`.           |
| `ready`       | out | 1     | Deasserted to stall the host (FIFO full, etc.).  |
| `error`       | out | 1     | Reserved; for unmapped accesses.                 |

`sst1_addr_decode` produces select strobes for:

- **Register space** — SST-1 control/status/setup registers.
- **LFB space** — linear frame-buffer access window (read/write pixels).
- **Texture memory space** — texture upload window.

Decode boundaries are parameters so simulations can run with small windows.

### 2.2 Register file (`sst1_regs`)

Synchronous register file, single-cycle read, single-cycle write. Reset
defaults follow the SST-1 spec. Triangle-setup registers feed
`sst1_triangle_setup`. Mode registers (`fbzMode`, `fbzColorPath`,
`alphaMode`, `fogMode`, `textureMode`, `lfbMode`, etc.) feed the pipeline
as bit-slice consumers.

Writes to the **command-trigger** register (e.g. `triangleCMD`,
`fastfillCMD`, `swapbufferCMD`) push an entry into the command FIFO. The
host-visible behavior is that those writes complete in one MMIO cycle
unless the FIFO is full, in which case `ready` is deasserted (back-pressure).

### 2.3 Command FIFO (`sst1_cmd_fifo`, `sst1_cmd_decoder`)

Synchronous, parameterized FIFO. Each entry encodes:

- Command type (triangle / fastfill / swapbuffer / nop / extended).
- A snapshot of the triangle-setup state at trigger time (so subsequent
  host writes don't disturb in-flight commands).

The decoder dispatches popped commands to `sst1_triangle_setup`,
`sst1_framebuffer` (for fastfill), or the swap-state machine.

### 2.4 Triangle setup (`sst1_triangle_setup`)

Captures vertex coordinates, color start/deltas (R, G, B, A), Z, S, T,
W, and clip/scissor state at command time. Exposes a stable record to
the rasterizer.

Initial fixed-point representation only. Floating-point register paths
(if any) are deferred until documented and isolated (Phase 8).

### 2.5 Rasterizer (`sst1_rasterizer`)

Edge-function rasterizer producing one in-triangle pixel per cycle on
average. Respects the clip registers (`clipLeftRight`, `clipBottomTop`).
Outputs pixel `(x, y)` plus the per-vertex barycentric weights or the
incrementally interpolated `R, G, B, A, Z, S, T, W` values needed by
downstream stages.

### 2.6 Interpolators & texture unit (`sst1_interp`, `sst1_texture_unit`, `sst1_texture_mem`)

- `sst1_interp` — fixed-point linear interpolation along scanlines.
- `sst1_texture_unit` — perspective division (S/W, T/W) and texel fetch.
  Nearest-neighbor first; bilinear and mip selection added in Phase 15.
- `sst1_texture_mem` — texture storage abstraction. BRAM-backed in
  simulation; SDRAM-backed in synthesis via the same interface.

### 2.7 Color combine, alpha, fog, dither

Per-pixel pipeline driven by mode registers:

- `sst1_color_combine` — implements `fbzColorPath` and texture combine.
- alpha test/blend — implements `alphaMode`.
- `sst1_fog` — implements `fogMode` (table fog initially approximated).
- `sst1_dither` — RGB ordered dither.
- chroma-key compare — implements `chromaKey`/`chromaRange`.

Order of operations follows the SST-1 spec and is cross-checked against
MAME's per-pixel ordering.

### 2.8 Z unit (`sst1_zunit`)

Z interpolation, depth compare (per `fbzMode`), conditional Z write to
the depth buffer.

### 2.9 Frame buffer (`sst1_framebuffer`, `sst1_lfb`)

`sst1_framebuffer` is the central memory abstraction for color buffer(s)
and depth buffer. Initially BRAM-friendly single-clock memory with the
same interface as later SDRAM/DDR wrappers.

`sst1_lfb` implements the LFB read/write window: pixel-format conversion
(per `lfbMode`), masking, and address mapping into `sst1_framebuffer`.

Double buffering is handled here at the address-translation layer; the
swap command flips the front/back selector.

### 2.10 Video scanout (`sst1_video_scanout`)

Reads the front buffer at video rate and emits a generic RGB pixel
stream (`pixel_valid`, `pixel_data`, `hsync`, `vsync`, `de`). A VGA/HDMI
wrapper can sit on top once the pixel stream is tested.

---

## 3. Clocking and reset

- **Single core clock domain** for the rendering pipeline in early phases.
  All flops are clocked on `clk` and reset by **synchronous active-high
  `rst`** (active-low equivalents are wrapped at the top level if needed).
- **Video clock domain** (`vid_clk`) for `sst1_video_scanout` and any
  pixel-stream output. Crossings are limited to the frame-buffer read
  port; an asynchronous BRAM read or a small CDC FIFO is used at that
  one boundary (decided in Phase 18).
- **Host clock domain** — initially the same as the core clock. A CDC
  bridge can be added once a real PCI front end is wrapped on.

All RTL uses synchronous logic. No latches. No combinational loops.

## 4. Memory partitioning

| Region            | Initial backing  | Synthesis target            |
|-------------------|------------------|-----------------------------|
| Color buffer(s)   | BRAM             | External SDRAM / DDR        |
| Depth buffer      | BRAM             | External SDRAM / DDR        |
| Texture memory    | BRAM             | External SDRAM / DDR        |
| Command FIFO      | BRAM/LUTRAM      | BRAM/LUTRAM (on-chip)       |
| Registers         | Flops            | Flops                       |

Sizes are parameters. Simulation defaults aim at 160×120 RGB565 + 16-bit
Z, which fits comfortably in BRAM on most mid-range FPGAs.

## 5. Accuracy roadmap

What is modeled **accurately first** (Phases 2–12):

- Register addresses, reset values, and bit-field semantics for the
  control/mode registers actually consumed by implemented stages.
- LFB read/write semantics for the pixel formats covered by tests.
- Edge-function rasterization for non-degenerate triangles within clip.
- Gouraud color interpolation with documented fixed-point precision.
- Z compare and write per `fbzMode`.
- Alpha test, alpha blend for the common modes covered by tests.

What is **approximated initially** (Phases 13–16):

- Texture filtering: nearest first, bilinear later. Mip LOD selection
  starts as the documented formula with a permissible approximation in
  the reciprocal path (`// APPROXIMATION:`).
- Perspective correction: per-pixel reciprocal initially via a small
  LUT + linear refinement, not the original ASIC's exact divider.
- Fog table: linear interpolation between table entries.
- Dither pattern: matches the spec ordered-dither matrix.

What is **deferred** (post-Phase 21 or out-of-scope):

- Cycle-level matching of the original ASIC's pipeline depth.
- SLI / multi-board behavior.
- Analog video DAC behavior (only digital pixel stream is produced).
- PCI configuration-space details beyond what the wrapper needs.

## 6. Testing strategy

- **Unit tests** per RTL block, under `sim/tb/`, named `tb_<module>.sv`.
- **Golden vectors** under `sim/vectors/` for interpolation, depth,
  blend, and texture sampling.
- **Integration tests** in Phase 19: write registers → push command →
  inspect frame buffer.
- **Compatibility tests** in Phase 20: software reference generates the
  expected pixels for a small scene; the RTL output is compared
  pixel-by-pixel.

## 7. Open questions

Tracked inline in RTL as `// TODO-COMPAT: ...`. Notable items expected
to appear:

- Exact rounding mode for color interpolation between vertices.
- Exact behavior of edge-tie-breaking on shared triangle edges.
- Exact LFB pixel-format expansion for less-common `lfbMode` settings.
- Fog table entry interpolation rule (linear vs. nearest).

These are resolved against MAME/PCem traces (and hardware traces where
available) during the relevant phase.
