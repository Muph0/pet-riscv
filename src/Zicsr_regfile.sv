interface CSR;

    logic msts_mie;
    logic msts_mpie;
    logic [1:0] msts_mpp;

    logic [31:2] mtv_base;
    logic [1:0] mtv_mode;

    modport inner(output msts_mie, msts_mpie, msts_mpp);

    modport intctl(input msts_mie);

endinterface

module Zicsr_regfile (
    input clk,
    input wr_en,
    input [11:0] adr,
    input [31:0] din,
    CSR.inner io,

    output [31:0] dout
);

    localparam MSTATUS = 12'h300;  // Machine Status: Controls state and global interrupt enable.
    reg [31:0] mstatus;
    assign io.msts_mie = mstatus[3];  // Machine Interrupt Enable. Set to 1 to allow interrupts in M-mode.
    assign io.msts_mpie = mstatus[7];  // Machine Previous Interrupt Enable. Saves the value of MIE when a trap is taken.
    assign io.msts_mpp = mstatus[12:11]; // Machine Previous Privilege. Saves the privilege mode before the trap.
    always_ff @(posedge clk) begin
        if (wr_en && adr == MSTATUS) mstatus <= din;
    end

    localparam MIE = 12'h304;  // Machine Interrupt Enable: Bitmask for specific interrupt types.
    reg [31:0] mie;
    always_ff @(posedge clk) begin
        if (wr_en && adr == MIE) mie <= din;
    end

    localparam MTVEC = 12'h305;  // Machine Trap-Vector Base: Entry point for the trap handler.
    reg [31:0] mtvec;
    assign io.mtv_base = mtvec[31:2];
    assign io.mtv_mode = mtvec[1:0];
    always_ff @(posedge clk) begin
        if (wr_en && adr == MTVEC) mtvec <= din;
    end

    localparam MEPC = 12'h341;  // Machine Exception PC: Saves PC of the interrupted instruction.
    reg [31:0] mepc;
    always_ff @(posedge clk) begin
        if (wr_en && adr == MEPC) mepc <= din;
    end

    localparam MCAUSE = 12'h342;  // Machine Cause: Indicates why the trap occurred.
    reg [31:0] mcause;
    always_ff @(posedge clk) begin
        if (wr_en && adr == MCAUSE) mcause <= din;
    end

    localparam MIP = 12'h344;  // Machine Interrupt Pending: Shows which interrupts are active.
    reg [31:0] mip;
    always_ff @(posedge clk) begin
        if (wr_en && adr == MIP) mip <= din;
    end

    localparam MCYCLE =     12'hB00; //Machine Cycle Counter: 64-bit cycle count (Lower 32-bits for RV32).
    reg [31:0] mcycle;
    always_ff @(posedge clk) begin
        if (wr_en && adr == MCYCLE) mcycle <= din;
    end

    localparam MINSTRET = 12'hB02;  // Instructions Retired: 64-bit count (Lower 32-bits for RV32).
    reg [31:0] minstret;
    always_ff @(posedge clk) begin
        if (wr_en && adr == MINSTRET) minstret <= din;
    end

    always_comb begin
        case (adr)
            MSTATUS: dout = mstatus;
            MIE: dout = mie;
            MTVEC: dout = mtvec;
            MEPC: dout = mepc;
            MCAUSE: dout = mcause;
            MIP: dout = mip;
            MCYCLE: dout = mcycle;
            MINSTRET: dout = minstret;
            default: dout = '0;
        endcase
    end

endmodule
