// -----------------------------------------------------------------------------
// sst1_regs.sv
// -----------------------------------------------------------------------------
// SST-1 memory-mapped register file (Phase 2 skeleton).
//
// Purpose
//   Holds the SST-1 control / mode / init / texture register state. Decodes
//   reads and writes against a 1 KB register window (256 x 32-bit). Surfaces
//   single-cycle command pulses for triangleCMD, ftriangleCMD, nopCMD,
//   fastfillCMD, and swapbufferCMD. Other phases will wire the stored
//   triangle parameters into sst1_triangle_setup and the mode bits into
//   the per-pixel pipeline.
//
// Clock/reset
//   Single synchronous clock domain (clk). Active-high synchronous reset
//   (rst). All flops are reset on rst=1. Reset defaults follow MAME for
//   the fbiInitN block (spec-unattested) and zero for everything else.
//
// Interface assumptions
//   - addr is the byte-address within the register window (lower 10 bits
//     select a 32-bit register via addr[9:2]). Address decoding for the
//     full BAR (registers / LFB / texture) is the job of sst1_addr_decode
//     in Phase 3; this module assumes the upstream decoder has already
//     selected the register window.
//   - we and re are mutually exclusive; if both are asserted in one cycle,
//     the write wins and the read returns whatever the register contains
//     after the write.
//   - be is the write byte-enable. Reads return the full 32-bit register
//     regardless of be.
//   - The module is always ready in Phase 2 (single-cycle response). FIFO
//     back-pressure for command-trigger writes is added when the command
//     FIFO is integrated (Phase 4).
//   - Writes to undefined / reserved register indices are accepted and
//     dropped. Reads from undefined indices return 32'h0.
//
// Fixed-point formats
//   N/A for the register file. Triangle-setup registers are stored as
//   raw 32-bit values; their fixed-point interpretation is consumed
//   downstream (sst1_fixed_pkg in Phase 5; sst1_triangle_setup in Phase 8).
//
// Sources
//   - SST-1 spec Rev 1.61
//   - MAME voodoo_regs.h / voodoo.cpp (cross-reference)
//   See docs/references.md for the attribution policy.
// -----------------------------------------------------------------------------

// Port widths are hardcoded to SST-1 spec values (24-bit address, 32-bit
// data, 4-bit byte enable). The shared sst1_consts.svh header is
// `\`include`d inside the module body so its localparams land in module
// scope; see the header for the rationale (Yosys SV-package limitations).
module sst1_regs (
  input  logic           clk,
  input  logic           rst,

  // MMIO bus (already address-decoded for the register window)
  input  logic [23:0]    bus_addr,
  input  logic           bus_we,
  input  logic           bus_re,
  input  logic [3:0]     bus_be,
  input  logic [31:0]    bus_wdata,
  output logic [31:0]    bus_rdata,
  output logic           bus_ready,

  // Command pulses (single-cycle, high on the cycle the trigger write
  // completes). Pulse data carries the wdata payload for the command.
  output logic           triangle_cmd_pulse,
  output logic           ftriangle_cmd_pulse,
  output logic           nop_cmd_pulse,
  output logic           fastfill_cmd_pulse,
  output logic           swapbuffer_cmd_pulse,
  output logic [31:0]    cmd_payload,

  // Mode-register taps used by other blocks in later phases.
  output logic [31:0]    fbz_mode,
  output logic [31:0]    fbz_colorpath,
  output logic [31:0]    alpha_mode,
  output logic [31:0]    fog_mode,
  output logic [31:0]    lfb_mode,
  output logic [31:0]    clip_lr,
  output logic [31:0]    clip_lowhigh_y,
  output logic [31:0]    fbi_init0,
  output logic [31:0]    fbi_init1,
  output logic [31:0]    fbi_init2,
  output logic [31:0]    fbi_init3,
  output logic [31:0]    fbi_init4
);

  `include "sst1_consts.svh"

  // ---------------------------------------------------------------------------
  // Local helpers
  // ---------------------------------------------------------------------------
  // Per-byte write mask derived from byte enables.
  logic [31:0] wmask;
  always_comb begin
    for (int i = 0; i < 4; i++) begin
      wmask[i*8 +: 8] = {8{bus_be[i]}};
    end
  end

  // Apply a write under byte-enable masking to a previous register value.
  // Verilog-2001 function form (input declarations and name-as-return,
  // no SV `return` statement) — chosen for Yosys 0.33 parser compatibility.
  function [31:0] masked;
    input [31:0] prev;
    input [31:0] wdata;
    input [31:0] mask;
    begin
      masked = (prev & ~mask) | (wdata & mask);
    end
  endfunction

  // Register index inside the 1 KB logical register map.
  wire [9:0] reg_off = bus_addr[9:0];

  // ---------------------------------------------------------------------------
  // RW mode registers
  // ---------------------------------------------------------------------------
  logic [BUS_DATA_BITS-1:0] r_fbz_mode;
  logic [BUS_DATA_BITS-1:0] r_fbz_colorpath;
  logic [BUS_DATA_BITS-1:0] r_alpha_mode;
  logic [BUS_DATA_BITS-1:0] r_fog_mode;
  logic [BUS_DATA_BITS-1:0] r_lfb_mode;
  logic [BUS_DATA_BITS-1:0] r_clip_lr;
  logic [BUS_DATA_BITS-1:0] r_clip_lowhigh_y;
  logic [BUS_DATA_BITS-1:0] r_stipple;
  logic [BUS_DATA_BITS-1:0] r_color0;
  logic [BUS_DATA_BITS-1:0] r_color1;

  // RW init/video block
  logic [BUS_DATA_BITS-1:0] r_fbi_init0;
  logic [BUS_DATA_BITS-1:0] r_fbi_init1;
  logic [BUS_DATA_BITS-1:0] r_fbi_init2;
  logic [BUS_DATA_BITS-1:0] r_fbi_init3;
  logic [BUS_DATA_BITS-1:0] r_fbi_init4;
  logic [BUS_DATA_BITS-1:0] r_back_porch;
  logic [BUS_DATA_BITS-1:0] r_video_dims;

  // Write-only storage (no readback path; future phases read these
  // through dedicated taps, not via the bus).
  logic [BUS_DATA_BITS-1:0] r_fog_color;
  logic [BUS_DATA_BITS-1:0] r_za_color;
  logic [BUS_DATA_BITS-1:0] r_chroma_key;

  // Write-only triangle-setup parameter shadow (snapshot consumer added in
  // Phase 8). Stored here so writes are non-destructive.
  logic [BUS_DATA_BITS-1:0] r_vertex_ax, r_vertex_ay;
  logic [BUS_DATA_BITS-1:0] r_vertex_bx, r_vertex_by;
  logic [BUS_DATA_BITS-1:0] r_vertex_cx, r_vertex_cy;
  logic [BUS_DATA_BITS-1:0] r_start_r, r_start_g, r_start_b, r_start_z;
  logic [BUS_DATA_BITS-1:0] r_start_a, r_start_s, r_start_t, r_start_w;
  logic [BUS_DATA_BITS-1:0] r_drdx, r_dgdx, r_dbdx, r_dzdx;
  logic [BUS_DATA_BITS-1:0] r_dadx, r_dsdx, r_dtdx, r_dwdx;
  logic [BUS_DATA_BITS-1:0] r_drdy, r_dgdy, r_dbdy, r_dzdy;
  logic [BUS_DATA_BITS-1:0] r_dady, r_dsdy, r_dtdy, r_dwdy;

  // TMU block
  logic [BUS_DATA_BITS-1:0] r_tex_mode;
  logic [BUS_DATA_BITS-1:0] r_tlod;
  logic [BUS_DATA_BITS-1:0] r_tdetail;
  logic [BUS_DATA_BITS-1:0] r_tex_base, r_tex_base1, r_tex_base2, r_tex_base3_8;
  logic [BUS_DATA_BITS-1:0] r_trex_init0, r_trex_init1;

  // ---------------------------------------------------------------------------
  // Sequential write path + command-pulse generation
  // ---------------------------------------------------------------------------
  always_ff @(posedge clk) begin
    if (rst) begin
      // Mode registers
      r_fbz_mode        <= '0;
      r_fbz_colorpath   <= '0;
      r_alpha_mode      <= '0;
      r_fog_mode        <= '0;
      r_lfb_mode        <= '0;
      r_clip_lr         <= '0;
      r_clip_lowhigh_y  <= '0;
      r_stipple         <= '0;
      r_color0          <= '0;
      r_color1          <= '0;

      // Init / video
      // // TODO-COMPAT: spec-unattested defaults; verify against SST-1.
      r_fbi_init0       <= RST_FBI_INIT0;
      r_fbi_init1       <= RST_FBI_INIT1;
      r_fbi_init2       <= RST_FBI_INIT2;
      r_fbi_init3       <= RST_FBI_INIT3;
      r_fbi_init4       <= RST_FBI_INIT4;
      r_back_porch      <= '0;
      r_video_dims      <= '0;

      // Write-only storage
      r_fog_color       <= '0;
      r_za_color        <= '0;
      r_chroma_key      <= '0;

      // Triangle params
      r_vertex_ax <= '0; r_vertex_ay <= '0;
      r_vertex_bx <= '0; r_vertex_by <= '0;
      r_vertex_cx <= '0; r_vertex_cy <= '0;
      r_start_r <= '0; r_start_g <= '0; r_start_b <= '0; r_start_z <= '0;
      r_start_a <= '0; r_start_s <= '0; r_start_t <= '0; r_start_w <= '0;
      r_drdx <= '0; r_dgdx <= '0; r_dbdx <= '0; r_dzdx <= '0;
      r_dadx <= '0; r_dsdx <= '0; r_dtdx <= '0; r_dwdx <= '0;
      r_drdy <= '0; r_dgdy <= '0; r_dbdy <= '0; r_dzdy <= '0;
      r_dady <= '0; r_dsdy <= '0; r_dtdy <= '0; r_dwdy <= '0;

      // TMU
      r_tex_mode    <= '0;
      r_tlod        <= '0;
      r_tdetail     <= '0;
      r_tex_base    <= '0;
      r_tex_base1   <= '0;
      r_tex_base2   <= '0;
      r_tex_base3_8 <= '0;
      r_trex_init0  <= '0;
      r_trex_init1  <= '0;

      // Pulses
      triangle_cmd_pulse   <= 1'b0;
      ftriangle_cmd_pulse  <= 1'b0;
      nop_cmd_pulse        <= 1'b0;
      fastfill_cmd_pulse   <= 1'b0;
      swapbuffer_cmd_pulse <= 1'b0;
      cmd_payload          <= '0;
    end else begin
      // Default: pulses deassert each cycle. Set high below only on the
      // exact cycle of a trigger write.
      triangle_cmd_pulse   <= 1'b0;
      ftriangle_cmd_pulse  <= 1'b0;
      nop_cmd_pulse        <= 1'b0;
      fastfill_cmd_pulse   <= 1'b0;
      swapbuffer_cmd_pulse <= 1'b0;

      if (bus_we) begin
        // Byte-enable-masked write into the addressed register.
        unique case (reg_off)
          // ---- Mode / control -------------------------------------------------
          OFF_FBZ_COLORPATH : r_fbz_colorpath  <= masked(r_fbz_colorpath,  bus_wdata, wmask);
          OFF_FOG_MODE      : r_fog_mode       <= masked(r_fog_mode,       bus_wdata, wmask);
          OFF_ALPHA_MODE    : r_alpha_mode     <= masked(r_alpha_mode,     bus_wdata, wmask);
          OFF_FBZ_MODE      : r_fbz_mode       <= masked(r_fbz_mode,       bus_wdata, wmask);
          OFF_LFB_MODE      : r_lfb_mode       <= masked(r_lfb_mode,       bus_wdata, wmask);
          OFF_CLIP_LR       : r_clip_lr        <= masked(r_clip_lr,        bus_wdata, wmask);
          OFF_CLIP_LOWHIGH_Y: r_clip_lowhigh_y <= masked(r_clip_lowhigh_y, bus_wdata, wmask);
          OFF_STIPPLE       : r_stipple        <= masked(r_stipple,        bus_wdata, wmask);
          OFF_COLOR0        : r_color0         <= masked(r_color0,         bus_wdata, wmask);
          OFF_COLOR1        : r_color1         <= masked(r_color1,         bus_wdata, wmask);

          // ---- Write-only color/key -----------------------------------------
          OFF_FOG_COLOR     : r_fog_color      <= masked(r_fog_color,      bus_wdata, wmask);
          OFF_ZA_COLOR      : r_za_color       <= masked(r_za_color,       bus_wdata, wmask);
          OFF_CHROMA_KEY    : r_chroma_key     <= masked(r_chroma_key,     bus_wdata, wmask);

          // ---- Init / video block -------------------------------------------
          OFF_FBI_INIT0     : r_fbi_init0      <= masked(r_fbi_init0,      bus_wdata, wmask);
          OFF_FBI_INIT1     : r_fbi_init1      <= masked(r_fbi_init1,      bus_wdata, wmask);
          OFF_FBI_INIT2     : r_fbi_init2      <= masked(r_fbi_init2,      bus_wdata, wmask);
          OFF_FBI_INIT3     : r_fbi_init3      <= masked(r_fbi_init3,      bus_wdata, wmask);
          OFF_FBI_INIT4     : r_fbi_init4      <= masked(r_fbi_init4,      bus_wdata, wmask);
          OFF_BACK_PORCH    : r_back_porch     <= masked(r_back_porch,     bus_wdata, wmask);
          OFF_VIDEO_DIMS    : r_video_dims     <= masked(r_video_dims,     bus_wdata, wmask);

          // ---- Integer triangle parameter shadow ----------------------------
          OFF_VERTEX_AX     : r_vertex_ax      <= masked(r_vertex_ax,      bus_wdata, wmask);
          OFF_VERTEX_AY     : r_vertex_ay      <= masked(r_vertex_ay,      bus_wdata, wmask);
          OFF_VERTEX_BX     : r_vertex_bx      <= masked(r_vertex_bx,      bus_wdata, wmask);
          OFF_VERTEX_BY     : r_vertex_by      <= masked(r_vertex_by,      bus_wdata, wmask);
          OFF_VERTEX_CX     : r_vertex_cx      <= masked(r_vertex_cx,      bus_wdata, wmask);
          OFF_VERTEX_CY     : r_vertex_cy      <= masked(r_vertex_cy,      bus_wdata, wmask);
          OFF_START_R       : r_start_r        <= masked(r_start_r,        bus_wdata, wmask);
          OFF_START_G       : r_start_g        <= masked(r_start_g,        bus_wdata, wmask);
          OFF_START_B       : r_start_b        <= masked(r_start_b,        bus_wdata, wmask);
          OFF_START_Z       : r_start_z        <= masked(r_start_z,        bus_wdata, wmask);
          OFF_START_A       : r_start_a        <= masked(r_start_a,        bus_wdata, wmask);
          OFF_START_S       : r_start_s        <= masked(r_start_s,        bus_wdata, wmask);
          OFF_START_T       : r_start_t        <= masked(r_start_t,        bus_wdata, wmask);
          OFF_START_W       : r_start_w        <= masked(r_start_w,        bus_wdata, wmask);
          OFF_DRDX          : r_drdx           <= masked(r_drdx,           bus_wdata, wmask);
          OFF_DGDX          : r_dgdx           <= masked(r_dgdx,           bus_wdata, wmask);
          OFF_DBDX          : r_dbdx           <= masked(r_dbdx,           bus_wdata, wmask);
          OFF_DZDX          : r_dzdx           <= masked(r_dzdx,           bus_wdata, wmask);
          OFF_DADX          : r_dadx           <= masked(r_dadx,           bus_wdata, wmask);
          OFF_DSDX          : r_dsdx           <= masked(r_dsdx,           bus_wdata, wmask);
          OFF_DTDX          : r_dtdx           <= masked(r_dtdx,           bus_wdata, wmask);
          OFF_DWDX          : r_dwdx           <= masked(r_dwdx,           bus_wdata, wmask);
          OFF_DRDY          : r_drdy           <= masked(r_drdy,           bus_wdata, wmask);
          OFF_DGDY          : r_dgdy           <= masked(r_dgdy,           bus_wdata, wmask);
          OFF_DBDY          : r_dbdy           <= masked(r_dbdy,           bus_wdata, wmask);
          OFF_DZDY          : r_dzdy           <= masked(r_dzdy,           bus_wdata, wmask);
          OFF_DADY          : r_dady           <= masked(r_dady,           bus_wdata, wmask);
          OFF_DSDY          : r_dsdy           <= masked(r_dsdy,           bus_wdata, wmask);
          OFF_DTDY          : r_dtdy           <= masked(r_dtdy,           bus_wdata, wmask);
          OFF_DWDY          : r_dwdy           <= masked(r_dwdy,           bus_wdata, wmask);

          // ---- TMU block ----------------------------------------------------
          OFF_TEX_MODE        : r_tex_mode    <= masked(r_tex_mode,    bus_wdata, wmask);
          OFF_TLOD            : r_tlod        <= masked(r_tlod,        bus_wdata, wmask);
          OFF_TDETAIL         : r_tdetail     <= masked(r_tdetail,     bus_wdata, wmask);
          OFF_TEX_BASE_ADDR   : r_tex_base    <= masked(r_tex_base,    bus_wdata, wmask);
          OFF_TEX_BASE_ADDR1  : r_tex_base1   <= masked(r_tex_base1,   bus_wdata, wmask);
          OFF_TEX_BASE_ADDR2  : r_tex_base2   <= masked(r_tex_base2,   bus_wdata, wmask);
          OFF_TEX_BASE_ADDR3_8: r_tex_base3_8 <= masked(r_tex_base3_8, bus_wdata, wmask);
          OFF_TREX_INIT0      : r_trex_init0  <= masked(r_trex_init0,  bus_wdata, wmask);
          OFF_TREX_INIT1      : r_trex_init1  <= masked(r_trex_init1,  bus_wdata, wmask);

          // ---- Command-trigger registers (write-only; pulse out) ------------
          OFF_TRIANGLE_CMD : begin
            triangle_cmd_pulse <= 1'b1;
            cmd_payload        <= bus_wdata;
          end
          OFF_FTRIANGLE_CMD: begin
            ftriangle_cmd_pulse <= 1'b1;
            cmd_payload         <= bus_wdata;
          end
          OFF_NOP_CMD      : begin
            nop_cmd_pulse <= 1'b1;
            cmd_payload   <= bus_wdata;
          end
          OFF_FASTFILL_CMD : begin
            fastfill_cmd_pulse <= 1'b1;
            cmd_payload        <= bus_wdata;
          end
          OFF_SWAPBUFFER_CMD: begin
            swapbuffer_cmd_pulse <= 1'b1;
            cmd_payload          <= bus_wdata;
          end

          default: begin
            // Reserved / unimplemented / read-only-on-V1: silently drop.
          end
        endcase
      end
    end
  end

  // ---------------------------------------------------------------------------
  // Combinational read path
  // ---------------------------------------------------------------------------
  // bus_ready is always asserted in Phase 2 (no stalling).
  assign bus_ready = 1'b1;

  always_comb begin
    bus_rdata = '0;
    if (bus_re) begin
      unique case (reg_off)
        // Status: zero for now; bit-level definition lands with the FIFO
        // and per-pixel pipeline (Phases 4+).
        OFF_STATUS         : bus_rdata = 32'h0000_0000;

        // RW mode registers
        OFF_FBZ_COLORPATH  : bus_rdata = r_fbz_colorpath;
        OFF_FOG_MODE       : bus_rdata = r_fog_mode;
        OFF_ALPHA_MODE     : bus_rdata = r_alpha_mode;
        OFF_FBZ_MODE       : bus_rdata = r_fbz_mode;
        OFF_LFB_MODE       : bus_rdata = r_lfb_mode;
        OFF_CLIP_LR        : bus_rdata = r_clip_lr;
        OFF_CLIP_LOWHIGH_Y : bus_rdata = r_clip_lowhigh_y;
        OFF_STIPPLE        : bus_rdata = r_stipple;
        OFF_COLOR0         : bus_rdata = r_color0;
        OFF_COLOR1         : bus_rdata = r_color1;

        // Read-only counters (zero until instrumented)
        OFF_FBI_PIXELS_IN  : bus_rdata = 32'h0;
        OFF_FBI_CHROMA_FAIL: bus_rdata = 32'h0;
        OFF_FBI_ZFUNC_FAIL : bus_rdata = 32'h0;
        OFF_FBI_AFUNC_FAIL : bus_rdata = 32'h0;
        OFF_FBI_PIXELS_OUT : bus_rdata = 32'h0;

        // Init / video block (RW)
        OFF_FBI_INIT0      : bus_rdata = r_fbi_init0;
        OFF_FBI_INIT1      : bus_rdata = r_fbi_init1;
        OFF_FBI_INIT2      : bus_rdata = r_fbi_init2;
        OFF_FBI_INIT3      : bus_rdata = r_fbi_init3;
        OFF_FBI_INIT4      : bus_rdata = r_fbi_init4;
        OFF_BACK_PORCH     : bus_rdata = r_back_porch;
        OFF_VIDEO_DIMS     : bus_rdata = r_video_dims;
        OFF_V_RETRACE      : bus_rdata = 32'h0; // // TODO-COMPAT: live scanout pos in Phase 18

        default            : bus_rdata = 32'h0;
      endcase
    end
  end

  // ---------------------------------------------------------------------------
  // External taps
  // ---------------------------------------------------------------------------
  assign fbz_mode       = r_fbz_mode;
  assign fbz_colorpath  = r_fbz_colorpath;
  assign alpha_mode     = r_alpha_mode;
  assign fog_mode       = r_fog_mode;
  assign lfb_mode       = r_lfb_mode;
  assign clip_lr        = r_clip_lr;
  assign clip_lowhigh_y = r_clip_lowhigh_y;
  assign fbi_init0      = r_fbi_init0;
  assign fbi_init1      = r_fbi_init1;
  assign fbi_init2      = r_fbi_init2;
  assign fbi_init3      = r_fbi_init3;
  assign fbi_init4      = r_fbi_init4;

endmodule : sst1_regs
