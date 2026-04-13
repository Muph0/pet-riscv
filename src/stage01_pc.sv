interface pc_stage_io;

    // ---- Inputs to the PC stage ----
    logic        reset;
    logic        enable;  // CPU enabled (not loading)

    // Step control
    logic        step;  // pulse: execute one instruction
    logic        run;  // level: free-run mode

    // Control signals
    logic        pc_redirect;  // branch/jump redirect
    logic [31:2] pc_target;

    // ---- Outputs from the PC stage ----
    logic [31:0] pc;  // current PC value
    logic [31:0] pc_next;  // next PC (computed)
    logic        halted;  // CPU is halted

    modport in(input reset, enable, step, run, pc_redirect, pc_target, output pc, pc_next, halted);
    modport prev(input pc, pc_next);

endinterface


module pc_stage (
    input clk,
    pc_stage_io.in io
);

    typedef enum logic [1:0] {
        S_HALTED,
        S_STEPPING,
        S_RUNNING
    } state_t;

    state_t state;

    // Advance logic
    logic   advance;
    assign advance = (state == S_STEPPING) || (state == S_RUNNING);
    assign io.halted = (state == S_HALTED);

    assign io.pc_next = io.pc_redirect ? {io.pc_target, 2'b00} : io.pc + 4;

    always_ff @(posedge clk) begin
        if (io.reset) begin
            io.pc <= '0;
            state <= S_HALTED;
        end else if (!io.enable) begin
            state <= S_HALTED;
        end else begin
            // State transitions
            case (state)
                S_HALTED: begin
                    if (io.run) state <= S_RUNNING;
                    else if (io.step) state <= S_STEPPING;
                end
                S_STEPPING: begin
                    io.pc <= io.pc_next;
                    state <= S_HALTED;
                end
                S_RUNNING: begin
                    io.pc <= io.pc_next;
                    if (!io.run) state <= S_HALTED;
                end
                default: state <= S_HALTED;
            endcase
        end
    end

endmodule
