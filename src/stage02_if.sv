// IF stage I/O
interface stageIF_face;

    // Pipeline control
    logic        reset;
    logic        advance;

    // To next stage
    logic [31:0] instr;  // fetched instruction
    logic [31:0] pc;  // PC associated with fetched instruction

    // Wishbone stall (fetch in progress)
    logic        wb_stall;

    modport in(input reset, advance, output instr, pc, wb_stall);
    modport prev(input instr, pc);  // "prev" as seen by the next stage
    modport hazard(input wb_stall, output reset, advance);

endinterface


module stageIF (
    input                   clk,
          stageIF_face.in   io,
          stagePC_face.prev prev,
          wishbone.master   ibus
);

    // --- Fetch state machine ---
    //   S_FETCH — bus transaction in progress, waiting for ACK
    //   S_DONE  — instruction captured, pipeline may advance
    //
    // Reset (including halt) puts us in S_FETCH.  The bus is gated by
    // !io.reset, so no transactions fire while halted.  When halt
    // deasserts, io.reset drops and the bus starts fetching prev.pc
    // (= PC_RESET).  wb_stall keeps the front-end frozen until ACK.
    typedef enum logic {
        S_FETCH = 1'b0,
        S_DONE  = 1'b1
    } state_t;

    state_t state;

    // Captured instruction + associated PC (latched together on ACK)
    logic [31:0] instr_r;
    logic [31:0] pc_r;

    always_ff @(posedge clk) begin
        if (io.reset) begin
            state   <= S_FETCH;
            instr_r <= '0;
            pc_r    <= prev.pc;
        end else begin
            case (state)
                S_FETCH: begin
                    if (ibus.ack) begin
                        instr_r <= ibus.stom;
                        pc_r    <= prev.pc;
                        state   <= S_DONE;
                    end
                end

                S_DONE: begin
                    if (io.advance) state <= S_FETCH;
                end
            endcase
        end
    end

    // --- Drive instruction bus ---
    // During S_FETCH: prev.pc is stable (PC frozen by front stall).
    // During S_DONE+enable: early-start the next fetch with prev.pc_next
    //   (the PC stage is about to advance on this same posedge).
    // Bus is gated by !io.reset so no transactions fire during halt/flush.
    wire bus_active = ((state == S_FETCH) || (state == S_DONE && io.advance)) && !io.reset;

    assign ibus.adr    = (state == S_DONE && io.advance) ? prev.pc_next : prev.pc;
    assign ibus.mtos   = '0;
    assign ibus.sel    = 4'b1111;
    assign ibus.we     = 1'b0;
    assign ibus.cyc    = bus_active;
    assign ibus.stb    = bus_active;

    // Outputs to next stage — registered, in sync
    assign io.instr    = instr_r;
    assign io.pc       = pc_r;

    // Stall while fetch is in progress (registered state, no comb loop)
    assign io.wb_stall = (state == S_FETCH);

endmodule
