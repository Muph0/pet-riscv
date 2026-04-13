interface pc_stage_io;

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

endinterface


module pc_stage (
    input clk,
    pc_stage_io.in io
);

    assign io.pc_next = io.pc_redirect ? {io.pc_target, 2'b00} : io.pc + 4;

    always_ff @(posedge clk) begin
        if (io.reset)
            io.pc <= '0;
        else if (io.advance)
            io.pc <= io.pc_next;
    end

endmodule
