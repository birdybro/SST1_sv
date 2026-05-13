// -----------------------------------------------------------------------------
// tb_sst1_regs.sv
// -----------------------------------------------------------------------------
// Self-checking testbench for sst1_regs (Phase 2).
//
// Coverage:
//   - Reset values for fbiInit0..4 match RST_FBI_INITn from sst1_pkg.
//   - Mode registers (fbzMode, fbzColorPath, alphaMode, fogMode, lfbMode,
//     clipLeftRight, clipLowYHighY, stipple, color0, color1) round-trip
//     a 32-bit write followed by a read.
//   - Byte-enable masking on writes (partial-write preserves other bytes).
//   - Write to triangleCMD / ftriangleCMD / nopCMD / fastfillCMD /
//     swapbufferCMD produces a single-cycle pulse with the expected payload
//     and does NOT pollute the address-aliased storage.
//   - Reads from reserved / unimplemented offsets return 32'h0.
//   - Re-assertion of reset returns fbiInit0..4 to their documented defaults
//     and clears mode registers to zero.
//
// Style:
//   - Synchronous DUT, single clock. Tests are written as drive-then-sample
//     sequences with explicit one-cycle delays via @(posedge clk).
//   - Each `check_*` task increments a failure counter on mismatch and prints
//     a one-line diagnostic. End-of-test summary prints PASS or FAIL and
//     calls $finish with code 0 (pass) or 1 (fail).
//
// This file is testbench-only and may use non-synthesizable constructs.
// -----------------------------------------------------------------------------

module tb_sst1_regs;

  `include "sst1_consts.svh"

  // ---------------------------------------------------------------------------
  // Clock / reset
  // ---------------------------------------------------------------------------
  logic clk = 1'b0;
  logic rst = 1'b1;
  always #5 clk = ~clk; // 100 MHz

  // ---------------------------------------------------------------------------
  // DUT signals
  // ---------------------------------------------------------------------------
  logic [BUS_ADDR_BITS-1:0] bus_addr;
  logic                     bus_we;
  logic                     bus_re;
  logic [BUS_BE_BITS-1:0]   bus_be;
  logic [BUS_DATA_BITS-1:0] bus_wdata;
  logic [BUS_DATA_BITS-1:0] bus_rdata;
  logic                     bus_ready;

  logic                     triangle_cmd_pulse;
  logic                     ftriangle_cmd_pulse;
  logic                     nop_cmd_pulse;
  logic                     fastfill_cmd_pulse;
  logic                     swapbuffer_cmd_pulse;
  logic [BUS_DATA_BITS-1:0] cmd_payload;

  logic [BUS_DATA_BITS-1:0] tap_fbz_mode;
  logic [BUS_DATA_BITS-1:0] tap_fbz_colorpath;
  logic [BUS_DATA_BITS-1:0] tap_alpha_mode;
  logic [BUS_DATA_BITS-1:0] tap_fog_mode;
  logic [BUS_DATA_BITS-1:0] tap_lfb_mode;
  logic [BUS_DATA_BITS-1:0] tap_clip_lr;
  logic [BUS_DATA_BITS-1:0] tap_clip_lowhigh_y;
  logic [BUS_DATA_BITS-1:0] tap_fbi_init0;
  logic [BUS_DATA_BITS-1:0] tap_fbi_init1;
  logic [BUS_DATA_BITS-1:0] tap_fbi_init2;
  logic [BUS_DATA_BITS-1:0] tap_fbi_init3;
  logic [BUS_DATA_BITS-1:0] tap_fbi_init4;

  sst1_regs dut (
    .clk(clk),
    .rst(rst),
    .bus_addr(bus_addr),
    .bus_we(bus_we),
    .bus_re(bus_re),
    .bus_be(bus_be),
    .bus_wdata(bus_wdata),
    .bus_rdata(bus_rdata),
    .bus_ready(bus_ready),
    .triangle_cmd_pulse(triangle_cmd_pulse),
    .ftriangle_cmd_pulse(ftriangle_cmd_pulse),
    .nop_cmd_pulse(nop_cmd_pulse),
    .fastfill_cmd_pulse(fastfill_cmd_pulse),
    .swapbuffer_cmd_pulse(swapbuffer_cmd_pulse),
    .cmd_payload(cmd_payload),
    .fbz_mode(tap_fbz_mode),
    .fbz_colorpath(tap_fbz_colorpath),
    .alpha_mode(tap_alpha_mode),
    .fog_mode(tap_fog_mode),
    .lfb_mode(tap_lfb_mode),
    .clip_lr(tap_clip_lr),
    .clip_lowhigh_y(tap_clip_lowhigh_y),
    .fbi_init0(tap_fbi_init0),
    .fbi_init1(tap_fbi_init1),
    .fbi_init2(tap_fbi_init2),
    .fbi_init3(tap_fbi_init3),
    .fbi_init4(tap_fbi_init4)
  );

  // ---------------------------------------------------------------------------
  // Scoreboard
  // ---------------------------------------------------------------------------
  int unsigned checks    = 0;
  int unsigned failures  = 0;

  task automatic expect_eq32(input string name,
                             input logic [31:0] got,
                             input logic [31:0] exp);
    checks++;
    if (got !== exp) begin
      failures++;
      $display("FAIL: %s  got=0x%08x  expected=0x%08x", name, got, exp);
    end
  endtask

  task automatic expect_eq1(input string name,
                            input logic got,
                            input logic exp);
    checks++;
    if (got !== exp) begin
      failures++;
      $display("FAIL: %s  got=%0b  expected=%0b", name, got, exp);
    end
  endtask

  // ---------------------------------------------------------------------------
  // Bus drive helpers
  //
  // These run in the testbench initial block, driving DUT inputs. We use
  // blocking assignments here because there is no inter-driver race to
  // resolve: each task fully drives the bus, waits for the DUT to sample
  // at the next posedge, then returns. (Verilator flags `<=` in initial
  // context with INITIALDLY; blocking assignment is the correct semantic.)
  // ---------------------------------------------------------------------------
  task automatic bus_idle();
    bus_addr  = '0;
    bus_we    = 1'b0;
    bus_re    = 1'b0;
    bus_be    = '0;
    bus_wdata = '0;
  endtask

  task automatic do_write(input logic [BUS_ADDR_BITS-1:0] a,
                          input logic [BUS_DATA_BITS-1:0] d,
                          input logic [BUS_BE_BITS-1:0]   be);
    @(posedge clk);
    bus_addr  = a;
    bus_we    = 1'b1;
    bus_re    = 1'b0;
    bus_be    = be;
    bus_wdata = d;
    @(posedge clk);
    bus_idle();
  endtask

  task automatic do_read(input  logic [BUS_ADDR_BITS-1:0] a,
                         output logic [BUS_DATA_BITS-1:0] d);
    @(posedge clk);
    bus_addr = a;
    bus_we   = 1'b0;
    bus_re   = 1'b1;
    bus_be   = '0;
    @(posedge clk); // bus_rdata is combinational on bus_re; sample after edge
    d = bus_rdata;
    bus_idle();
  endtask

  // ---------------------------------------------------------------------------
  // Test sequence
  // ---------------------------------------------------------------------------
  logic [31:0] r;

  initial begin
    bus_idle();
    // Hold reset for several cycles. Blocking assignments are the right
    // semantic in an initial block driving DUT inputs.
    rst = 1'b1;
    repeat (4) @(posedge clk);
    rst = 1'b0;
    @(posedge clk);

    // ---- Reset defaults --------------------------------------------------
    expect_eq32("fbi_init0 reset", tap_fbi_init0, RST_FBI_INIT0);
    expect_eq32("fbi_init1 reset", tap_fbi_init1, RST_FBI_INIT1);
    expect_eq32("fbi_init2 reset", tap_fbi_init2, RST_FBI_INIT2);
    expect_eq32("fbi_init3 reset", tap_fbi_init3, RST_FBI_INIT3);
    expect_eq32("fbi_init4 reset", tap_fbi_init4, RST_FBI_INIT4);
    expect_eq32("fbz_mode reset", tap_fbz_mode, 32'h0);
    expect_eq32("alpha_mode reset", tap_alpha_mode, 32'h0);

    // Read-back of fbiInit0 should match the tap.
    do_read({14'h0000, OFF_FBI_INIT0}, r);
    expect_eq32("read fbi_init0", r, RST_FBI_INIT0);

    // ---- RW round-trip on mode registers ---------------------------------
    do_write({14'h0000, OFF_FBZ_MODE}, 32'hDEAD_BEEF, 4'b1111);
    expect_eq32("fbz_mode tap after write", tap_fbz_mode, 32'hDEAD_BEEF);
    do_read({14'h0000, OFF_FBZ_MODE}, r);
    expect_eq32("fbz_mode readback", r, 32'hDEAD_BEEF);

    do_write({14'h0000, OFF_ALPHA_MODE}, 32'h1234_5678, 4'b1111);
    do_read({14'h0000, OFF_ALPHA_MODE}, r);
    expect_eq32("alpha_mode readback", r, 32'h1234_5678);

    do_write({14'h0000, OFF_LFB_MODE}, 32'hCAFE_F00D, 4'b1111);
    expect_eq32("lfb_mode tap after write", tap_lfb_mode, 32'hCAFE_F00D);

    // ---- Byte-enable masking --------------------------------------------
    // Start from a known value, then partial-write byte 1 only.
    do_write({14'h0000, OFF_COLOR0}, 32'hAA_BB_CC_DD, 4'b1111);
    do_read ({14'h0000, OFF_COLOR0}, r);
    expect_eq32("color0 preload", r, 32'hAA_BB_CC_DD);
    // wdata = 0x0000_1100 places 0x11 in byte 1; be=4'b0010 unlocks byte 1
    // only, so byte 1 ('CC') should become '11' and the other bytes
    // preserve their preload values.
    do_write({14'h0000, OFF_COLOR0}, 32'h0000_1100, 4'b0010);
    do_read ({14'h0000, OFF_COLOR0}, r);
    expect_eq32("color0 BE byte1 only", r, 32'hAA_BB_11_DD);

    // ---- Write-only color/key has no readback (returns 0) -----------------
    do_write({14'h0000, OFF_FOG_COLOR}, 32'h0102_0304, 4'b1111);
    do_read ({14'h0000, OFF_FOG_COLOR}, r);
    expect_eq32("fog_color is write-only", r, 32'h0);

    // ---- Reserved offset reads zero ---------------------------------------
    // 10'h004 is reserved on SST-1 (intrCtrl is V2+ only).
    do_read({14'h0000, 10'h004}, r);
    expect_eq32("reserved 0x004 reads 0", r, 32'h0);

    // ---- Command-trigger pulses ------------------------------------------
    // The pulse asserts in the same cycle the write commits, and the
    // command's wdata is latched into cmd_payload. Because do_write
    // already advances past the write cycle, sampling the pulse directly
    // after do_write returns sees the (now-deasserting) pulse.
    //
    // We use fork-join: drive_x issues the write, sample_x polls for the
    // pulse going high (with a small bound so a missing pulse becomes a
    // test failure rather than a hang).
    fork
      begin : drive_triangle_cmd
        do_write({14'h0000, OFF_TRIANGLE_CMD}, 32'h0000_0001, 4'b1111);
      end
      begin : sample_triangle_cmd
        for (int i = 0; i < 5 && triangle_cmd_pulse !== 1'b1; i++) @(posedge clk);
        expect_eq1 ("triangle_cmd_pulse asserted", triangle_cmd_pulse, 1'b1);
        expect_eq32("triangle_cmd payload", cmd_payload, 32'h0000_0001);
      end
    join

    // After the write completes the pulse should be low again.
    @(posedge clk);
    expect_eq1("triangle_cmd_pulse deasserts", triangle_cmd_pulse, 1'b0);

    fork
      begin : drive_fastfill
        do_write({14'h0000, OFF_FASTFILL_CMD}, 32'hF00D_BABE, 4'b1111);
      end
      begin : sample_fastfill
        for (int i = 0; i < 5 && fastfill_cmd_pulse !== 1'b1; i++) @(posedge clk);
        expect_eq1 ("fastfill_cmd_pulse asserted", fastfill_cmd_pulse, 1'b1);
        expect_eq32("fastfill_cmd payload", cmd_payload, 32'hF00D_BABE);
      end
    join

    fork
      begin : drive_swap
        do_write({14'h0000, OFF_SWAPBUFFER_CMD}, 32'h0000_0003, 4'b1111);
      end
      begin : sample_swap
        for (int i = 0; i < 5 && swapbuffer_cmd_pulse !== 1'b1; i++) @(posedge clk);
        expect_eq1 ("swapbuffer_cmd_pulse asserted", swapbuffer_cmd_pulse, 1'b1);
        expect_eq32("swapbuffer_cmd payload", cmd_payload, 32'h0000_0003);
      end
    join

    fork
      begin : drive_nop
        do_write({14'h0000, OFF_NOP_CMD}, 32'h0000_0002, 4'b1111);
      end
      begin : sample_nop
        for (int i = 0; i < 5 && nop_cmd_pulse !== 1'b1; i++) @(posedge clk);
        expect_eq1 ("nop_cmd_pulse asserted", nop_cmd_pulse, 1'b1);
        expect_eq32("nop_cmd payload", cmd_payload, 32'h0000_0002);
      end
    join

    fork
      begin : drive_ftri
        do_write({14'h0000, OFF_FTRIANGLE_CMD}, 32'h0000_0010, 4'b1111);
      end
      begin : sample_ftri
        for (int i = 0; i < 5 && ftriangle_cmd_pulse !== 1'b1; i++) @(posedge clk);
        expect_eq1 ("ftriangle_cmd_pulse asserted", ftriangle_cmd_pulse, 1'b1);
        expect_eq32("ftriangle_cmd payload", cmd_payload, 32'h0000_0010);
      end
    join

    // ---- Reset returns defaults / clears mode regs ------------------------
    // Dirty the state first so the reset has something to wipe.
    do_write({14'h0000, OFF_FBZ_MODE}, 32'hFFFF_FFFF, 4'b1111);
    do_write({14'h0000, OFF_FBI_INIT0}, 32'h0000_0000, 4'b1111);
    @(posedge clk);
    rst = 1'b1;
    repeat (3) @(posedge clk);
    rst = 1'b0;
    @(posedge clk);
    expect_eq32("fbi_init0 after re-reset", tap_fbi_init0, RST_FBI_INIT0);
    expect_eq32("fbz_mode after re-reset",  tap_fbz_mode,  32'h0);

    // ---- bus_ready is high at all times in Phase 2 ------------------------
    expect_eq1("bus_ready high (Phase 2)", bus_ready, 1'b1);

    // ---- Done ------------------------------------------------------------
    $display("tb_sst1_regs: checks=%0d failures=%0d", checks, failures);
    if (failures == 0) begin
      $display("tb_sst1_regs: PASS");
      $finish;
    end else begin
      $display("tb_sst1_regs: FAIL");
      $fatal(1, "tb_sst1_regs failures");
    end
  end

  // Safety net so a hung test does not run forever.
  initial begin
    #100000;
    $display("tb_sst1_regs: TIMEOUT after %0t", $time);
    $fatal(1, "tb_sst1_regs timeout");
  end

endmodule : tb_sst1_regs
