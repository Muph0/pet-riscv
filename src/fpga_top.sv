// =============================================================================
// fpga_top — Physical top-level for GW2A-18C
//
// Pin → CST mapping: see pinout.md for full reference
//
//
// DDR bus is now fully internal to cpu_top — fpga_top only exposes physical pins.
// When a DDR PHY IP is added, it will be instantiated here alongside cpu_top.
// =============================================================================
module fpga_top (
    input logic clk27,
    input logic key2,   // Silicone Key 2 — resets bootloader (active low)

    input  logic pin_rx,
    output logic pin_tx,

    output logic led4,
    output logic led5,

    // DDR3 Pins
    output logic [14-1:0] ddr_addr,
    output logic [ 3-1:0] ddr_bank,
    output logic          ddr_cs,
    output logic          ddr_ras,
    output logic          ddr_cas,
    output logic          ddr_we,
    output logic          ddr_ck,
    output logic          ddr_ck_n,
    output logic          ddr_cke,
    output logic          ddr_odt,
    output logic          ddr_reset_n,
    output logic [ 2-1:0] ddr_dm,
    inout  logic [16-1:0] ddr_dq,
    inout  logic [ 2-1:0] ddr_dqs,
    inout  logic [ 2-1:0] ddr_dqs_n

);

    // Provide clock/reset for the Wishbone external memory bus
    logic por = 1'b1;
    always_ff @(posedge clk27) por <= 1'b0;
    logic key2_s1 = 1'b1, key2_s2 = 1'b1;
    always_ff @(posedge clk27) begin
        key2_s1 <= key2;
        key2_s2 <= key2_s1;
    end
    wire reset = por | ~key2_s2;

    wishbone ddr_bus (
        .clk  (clk27),
        .reset(reset)
    );

    logic [1:0] ddr_status;

    cpu_top u_cpu (
        .clk27,
        .key2,
        .pin_rx,
        .pin_tx,
        .led4,
        .led5,
        .ext_ddr_bus(ddr_bus),
        .ext_ddr_status(ddr_status)
    );

    wb_ddr3 u_ddr3 (
        .clk          (clk27),
        .bus          (ddr_bus),
        .ddr_status   (ddr_status),
        .O_ddr_addr   (ddr_addr),
        .O_ddr_ba     (ddr_bank),
        .O_ddr_cs_n   (ddr_cs),
        .O_ddr_ras_n  (ddr_ras),
        .O_ddr_cas_n  (ddr_cas),
        .O_ddr_we_n   (ddr_we),
        .O_ddr_clk    (ddr_ck),
        .O_ddr_clk_n  (ddr_ck_n),
        .O_ddr_cke    (ddr_cke),
        .O_ddr_odt    (ddr_odt),
        .O_ddr_reset_n(ddr_reset_n),
        .O_ddr_dqm    (ddr_dm),
        .IO_ddr_dq    (ddr_dq),
        .IO_ddr_dqs   (ddr_dqs),
        .IO_ddr_dqs_n (ddr_dqs_n)
    );

endmodule
