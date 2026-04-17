interface stagePC_face;

    // ---- Inputs to the PC stage ----
    logic        reset;
    logic        advance;  // pulse: advance PC by one instruction

    // Control signals
    logic        pc_redirect;  // branch/jump redirect
    logic [31:2] pc_target;

    // ---- Outputs from the PC stage ----
    logic [31:0] pc;  // current PC value
    logic [31:0] pc_next;  // next PC (computed)

    modport in(input reset, advance, pc_redirect, pc_target, output pc, pc_next);
    modport prev(input pc, pc_next);
    modport hazard(output reset, advance);

endinterface


module stagePC #(
    parameter logic [31:0] PC_RESET = 32'h0000_1000
) (
    input clk,
    stagePC_face.in io
);

    assign io.pc_next = io.pc_redirect ? {io.pc_target, 2'b00} : io.pc + 4;

    always_ff @(posedge clk) begin
        if (io.reset) io.pc <= PC_RESET;
        else if (io.advance) io.pc <= io.pc_next;
    end

endmodule
