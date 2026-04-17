// =============================================================================
// fpga_top — Physical top-level for GW2A-18C
//
// Pin → CST mapping:
//   clk27   H11   LVCMOS33   27 MHz oscillator
//   pin_rx  T13   LVCMOS33   UART RX from host
//   pin_tx  M11   LVCMOS33   UART TX to host
//   led4    L14   LVCMOS33   status LED
//   led5    L16   LVCMOS33   status LED
//   pin_p9  P9    LVCMOS18   reserved (DDR / future PHY use)
//
// DDR bus is now fully internal to cpu_top — fpga_top only exposes physical pins.
// When a DDR PHY IP is added, it will be instantiated here alongside cpu_top.
// =============================================================================
module fpga_top (
    input logic clk27,

    input  logic pin_rx,
    output logic pin_tx,

    output logic led4,
    output logic led5,

    input logic pin_p9  // reserved — DDR strobe / future use
);

    cpu_top u_cpu (
        .clk27,
        .pin_rx,
        .pin_tx,
        .led4,
        .led5
    );

endmodule
