// -----------------------------------------------------------------------------
// sst1_consts.svh
// -----------------------------------------------------------------------------
// Shared parameters, register address offsets, and reset defaults for the
// SST-1 (3dfx Voodoo Graphics) reimplementation.
//
// Form:
//   `include`-able header of `localparam` declarations. Intended to be
//   placed inside a module body. Each consumer module gets a private copy
//   of the constants in its own scope.
//
// Why a header instead of a SystemVerilog package:
//   Yosys 0.33's vanilla `read_verilog -sv` does not parse package-scope
//   references (`pkg::*` / `pkg::SYM` raise TOK_PACKAGESEP errors). Until
//   the project adopts a Yosys with the slang plugin or moves to a newer
//   Yosys with full SV-package support, a `localparam` header is the
//   lowest-common-denominator that both Verilator and Yosys accept.
//
//   Style impact: no `import`, no `::` references. Modules write
//   `OFF_FBZ_MODE` directly because the localparams land in module scope.
//
// Include semantics:
//   - DO NOT add an `ifndef/define` include guard here. Each module that
//     includes this file should get a fresh declaration in its own scope;
//     a guard would suppress the second module's copy and leave its
//     references unresolved.
//   - Include this file at most ONCE per module body.
//
// Sources
//   - SST-1 spec Rev 1.61 (primary)
//   - MAME voodoo_regs.h / voodoo.cpp (cross-reference)
//   - PCem vid_voodoo*.c (independent cross-check)
//   See docs/references.md.
//
// Notes
//   - V2+/Banshee-only registers are intentionally omitted on a pure
//     SST-1 build.
//   - Reset values for fbiInit0..4 are not published in the public spec.
//     Defaults below are MAME's chosen defaults; they are NOT
//     silicon-attested.
// -----------------------------------------------------------------------------

// ---- Bus geometry --------------------------------------------------------
localparam int unsigned BUS_ADDR_BITS = 24;
localparam int unsigned BUS_DATA_BITS = 32;
localparam int unsigned BUS_BE_BITS   = 4;

// ---- BAR partitioning ----------------------------------------------------
//   [0x000000 .. 0x3FFFFF]  Register window (4 MB, mirrored over 1 KB map)
//   [0x400000 .. 0x7FFFFF]  LFB window      (4 MB)
//   [0x800000 .. 0xFFFFFF]  Texture window  (4 MB write-only)
localparam logic [23:0] REG_WINDOW_BASE = 24'h00_0000;
localparam logic [23:0] LFB_WINDOW_BASE = 24'h40_0000;
localparam logic [23:0] TEX_WINDOW_BASE = 24'h80_0000;
localparam logic [23:0] WINDOW_SIZE     = 24'h40_0000;

// ---- Register region geometry --------------------------------------------
localparam int unsigned NUM_REGS     = 256;
localparam int unsigned REG_IDX_BITS = 8;

// ---- Register byte offsets within the 1 KB logical map ------------------
// Status / control
localparam logic [9:0] OFF_STATUS         = 10'h000;
// 10'h004 reserved on SST-1 (intrCtrl is V2+ only)

// Integer triangle parameters (snapshot set)
localparam logic [9:0] OFF_VERTEX_AX      = 10'h008;
localparam logic [9:0] OFF_VERTEX_AY      = 10'h00C;
localparam logic [9:0] OFF_VERTEX_BX      = 10'h010;
localparam logic [9:0] OFF_VERTEX_BY      = 10'h014;
localparam logic [9:0] OFF_VERTEX_CX      = 10'h018;
localparam logic [9:0] OFF_VERTEX_CY      = 10'h01C;

localparam logic [9:0] OFF_START_R        = 10'h020;
localparam logic [9:0] OFF_START_G        = 10'h024;
localparam logic [9:0] OFF_START_B        = 10'h028;
localparam logic [9:0] OFF_START_Z        = 10'h02C;
localparam logic [9:0] OFF_START_A        = 10'h030;
localparam logic [9:0] OFF_START_S        = 10'h034;
localparam logic [9:0] OFF_START_T        = 10'h038;
localparam logic [9:0] OFF_START_W        = 10'h03C;

localparam logic [9:0] OFF_DRDX           = 10'h040;
localparam logic [9:0] OFF_DGDX           = 10'h044;
localparam logic [9:0] OFF_DBDX           = 10'h048;
localparam logic [9:0] OFF_DZDX           = 10'h04C;
localparam logic [9:0] OFF_DADX           = 10'h050;
localparam logic [9:0] OFF_DSDX           = 10'h054;
localparam logic [9:0] OFF_DTDX           = 10'h058;
localparam logic [9:0] OFF_DWDX           = 10'h05C;

localparam logic [9:0] OFF_DRDY           = 10'h060;
localparam logic [9:0] OFF_DGDY           = 10'h064;
localparam logic [9:0] OFF_DBDY           = 10'h068;
localparam logic [9:0] OFF_DZDY           = 10'h06C;
localparam logic [9:0] OFF_DADY           = 10'h070;
localparam logic [9:0] OFF_DSDY           = 10'h074;
localparam logic [9:0] OFF_DTDY           = 10'h078;
localparam logic [9:0] OFF_DWDY           = 10'h07C;

// Integer triangle command trigger
localparam logic [9:0] OFF_TRIANGLE_CMD   = 10'h080;
// 10'h084 reserved

// Float triangle parameters (mirror layout of the integer block)
localparam logic [9:0] OFF_FVERTEX_AX     = 10'h088;
localparam logic [9:0] OFF_FVERTEX_AY     = 10'h08C;
localparam logic [9:0] OFF_FVERTEX_BX     = 10'h090;
localparam logic [9:0] OFF_FVERTEX_BY     = 10'h094;
localparam logic [9:0] OFF_FVERTEX_CX     = 10'h098;
localparam logic [9:0] OFF_FVERTEX_CY     = 10'h09C;
localparam logic [9:0] OFF_FSTART_R       = 10'h0A0;
localparam logic [9:0] OFF_FSTART_G       = 10'h0A4;
localparam logic [9:0] OFF_FSTART_B       = 10'h0A8;
localparam logic [9:0] OFF_FSTART_Z       = 10'h0AC;
localparam logic [9:0] OFF_FSTART_A       = 10'h0B0;
localparam logic [9:0] OFF_FSTART_S       = 10'h0B4;
localparam logic [9:0] OFF_FSTART_T       = 10'h0B8;
localparam logic [9:0] OFF_FSTART_W       = 10'h0BC;
localparam logic [9:0] OFF_FDRDX          = 10'h0C0;
localparam logic [9:0] OFF_FDGDX          = 10'h0C4;
localparam logic [9:0] OFF_FDBDX          = 10'h0C8;
localparam logic [9:0] OFF_FDZDX          = 10'h0CC;
localparam logic [9:0] OFF_FDADX          = 10'h0D0;
localparam logic [9:0] OFF_FDSDX          = 10'h0D4;
localparam logic [9:0] OFF_FDTDX          = 10'h0D8;
localparam logic [9:0] OFF_FDWDX          = 10'h0DC;
localparam logic [9:0] OFF_FDRDY          = 10'h0E0;
localparam logic [9:0] OFF_FDGDY          = 10'h0E4;
localparam logic [9:0] OFF_FDBDY          = 10'h0E8;
localparam logic [9:0] OFF_FDZDY          = 10'h0EC;
localparam logic [9:0] OFF_FDADY          = 10'h0F0;
localparam logic [9:0] OFF_FDSDY          = 10'h0F4;
localparam logic [9:0] OFF_FDTDY          = 10'h0F8;
localparam logic [9:0] OFF_FDWDY          = 10'h0FC;
localparam logic [9:0] OFF_FTRIANGLE_CMD  = 10'h100;

// Mode / control (per-triangle and global)
localparam logic [9:0] OFF_FBZ_COLORPATH  = 10'h104;
localparam logic [9:0] OFF_FOG_MODE       = 10'h108;
localparam logic [9:0] OFF_ALPHA_MODE     = 10'h10C;
localparam logic [9:0] OFF_FBZ_MODE       = 10'h110;
localparam logic [9:0] OFF_LFB_MODE       = 10'h114;
localparam logic [9:0] OFF_CLIP_LR        = 10'h118;
localparam logic [9:0] OFF_CLIP_LOWHIGH_Y = 10'h11C;

// Command triggers (write-only; produce single-cycle pulses)
localparam logic [9:0] OFF_NOP_CMD        = 10'h120;
localparam logic [9:0] OFF_FASTFILL_CMD   = 10'h124;
localparam logic [9:0] OFF_SWAPBUFFER_CMD = 10'h128;

localparam logic [9:0] OFF_FOG_COLOR      = 10'h12C;
localparam logic [9:0] OFF_ZA_COLOR       = 10'h130;
localparam logic [9:0] OFF_CHROMA_KEY     = 10'h134;
// 10'h138 chromaRange  - V2+ only, reserved on SST-1
// 10'h13C userIntrCMD  - V2+ only, reserved on SST-1

localparam logic [9:0] OFF_STIPPLE        = 10'h140;
localparam logic [9:0] OFF_COLOR0         = 10'h144;
localparam logic [9:0] OFF_COLOR1         = 10'h148;

// Read-only counters (return zero until instrumentation is added)
localparam logic [9:0] OFF_FBI_PIXELS_IN  = 10'h14C;
localparam logic [9:0] OFF_FBI_CHROMA_FAIL= 10'h150;
localparam logic [9:0] OFF_FBI_ZFUNC_FAIL = 10'h154;
localparam logic [9:0] OFF_FBI_AFUNC_FAIL = 10'h158;
localparam logic [9:0] OFF_FBI_PIXELS_OUT = 10'h15C;

// Fog table: 32 entries @ +0x160 .. +0x1DC
localparam logic [9:0] OFF_FOG_TABLE_BASE = 10'h160;
localparam int unsigned FOG_TABLE_ENTRIES = 32;

// FBI init / video config block
localparam logic [9:0] OFF_FBI_INIT4      = 10'h200;
localparam logic [9:0] OFF_V_RETRACE      = 10'h204; // read-only
localparam logic [9:0] OFF_BACK_PORCH     = 10'h208;
localparam logic [9:0] OFF_VIDEO_DIMS     = 10'h20C;
localparam logic [9:0] OFF_FBI_INIT0      = 10'h210;
localparam logic [9:0] OFF_FBI_INIT1      = 10'h214;
localparam logic [9:0] OFF_FBI_INIT2      = 10'h218;
localparam logic [9:0] OFF_FBI_INIT3      = 10'h21C;
localparam logic [9:0] OFF_HSYNC          = 10'h220; // write-only timing
localparam logic [9:0] OFF_VSYNC          = 10'h224;
localparam logic [9:0] OFF_CLUT_DATA      = 10'h228;
localparam logic [9:0] OFF_DAC_DATA       = 10'h22C;
localparam logic [9:0] OFF_MAX_RGB_DELTA  = 10'h230;

// TMU register block (single window; chip-mask is encoded by FIFO path)
localparam logic [9:0] OFF_TEX_MODE         = 10'h300;
localparam logic [9:0] OFF_TLOD             = 10'h304;
localparam logic [9:0] OFF_TDETAIL          = 10'h308;
localparam logic [9:0] OFF_TEX_BASE_ADDR    = 10'h30C;
localparam logic [9:0] OFF_TEX_BASE_ADDR1   = 10'h310;
localparam logic [9:0] OFF_TEX_BASE_ADDR2   = 10'h314;
localparam logic [9:0] OFF_TEX_BASE_ADDR3_8 = 10'h318;
localparam logic [9:0] OFF_TREX_INIT0       = 10'h31C;
localparam logic [9:0] OFF_TREX_INIT1       = 10'h320;

// NCC tables (Y / I / Q): block at 10'h324 .. ~10'h37C, modeled as
// generic write-only storage in later phases. Not implemented in Phase 2.

// ---- Reset defaults ------------------------------------------------------
//   The SST-1 spec does not publish silicon power-on defaults for fbiInitN.
//   Defaults below match MAME (mamedev/mame voodoo.cpp) so software that
//   inherits MAME-compatible behavior boots cleanly.
//   // TODO-COMPAT: verify against SST-1 hardware traces if available.
localparam logic [31:0] RST_FBI_INIT0 = 32'h0000_0401;
localparam logic [31:0] RST_FBI_INIT1 = 32'h0020_1302;
localparam logic [31:0] RST_FBI_INIT2 = 32'h0800_0040;
localparam logic [31:0] RST_FBI_INIT3 = 32'h0007_A000;
localparam logic [31:0] RST_FBI_INIT4 = 32'h0000_0001;
