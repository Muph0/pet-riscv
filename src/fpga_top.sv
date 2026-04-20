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
    output logic led5

);

    cpu_top u_cpu (
        .clk27,
        .key2,
        .pin_rx,
        .pin_tx,
        .led4,
        .led5
    );

endmodule
