`timescale 1ns/1ps

module rPLL (
    input  clkin,
    input  clkfb,
    input  reset,
    input  reset_p,
    input  [5:0] fbdsel,
    input  [5:0] idsel,
    input  [5:0] odsel,
    input  [3:0] dutyda,
    input  [3:0] psda,
    input  [3:0] fdly,
    output clkout,
    output lock,
    output clkoutp,
    output clkoutd,
    output clkoutd3
);

    parameter FCLKIN = "100.0";
    parameter DYN_IDIV_SEL = "false";
    parameter IDIV_SEL = 0;
    parameter DYN_FBDIV_SEL = "false";
    parameter FBDIV_SEL = 0;
    parameter DYN_ODIV_SEL = "false";
    parameter ODIV_SEL = 8;
    parameter PSDA_SEL = "0000";
    parameter DYN_DA_EN = "true";
    parameter DUTYDA_SEL = "1000";
    parameter CLKOUT_FT_DIR = 1'b1;
    parameter CLKOUTP_FT_DIR = 1'b1;
    parameter CLKOUT_DLY_STEP = 0;
    parameter CLKOUTP_DLY_STEP = 0;
    parameter CLKFB_SEL = "internal";
    parameter CLKOUT_BYPASS = "false";
    parameter CLKOUTP_BYPASS = "false";
    parameter CLKOUTD_BYPASS = "false";
    parameter DYN_SDIV_SEL = 2;
    parameter CLKOUTD_SRC = "CLKOUT";
    parameter CLKOUTD3_SRC = "CLKOUT";

    // Simple pass-through or static division for simulation
    // In actual simulation, we just want a clock and a lock signal.
    reg out_clk = 0;
    reg locked = 0;

    always #5 out_clk = ~out_clk; // Assuming a mock 100MHz clock

    initial begin
        locked = 0;
        #100 locked = 1;
    end

    // During reset, lose lock
    always @(posedge reset) begin
        locked <= 0;
    end
    always @(negedge reset) begin
        #100 locked <= 1;
    end

    assign clkout = out_clk;
    assign clkoutp = out_clk;
    assign clkoutd = out_clk;
    assign clkoutd3 = out_clk;
    assign lock = locked;

endmodule
