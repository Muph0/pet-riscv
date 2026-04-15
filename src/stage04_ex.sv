interface stageEX_face;
    import mem_pkg::*;

    // Pipeline control
    logic             reset;
    logic             enable;
    // Forwarding
    logic             fw_mem;
    logic             fw_wb;

    // ALU result
    logic      [31:0] alu_result;

    // Memory (passed through)
    logic      [31:0] op_mem;
    mem_mode_t        mem_mode;
    width_t           mem_width;

    // Register tracking
    logic      [ 4:0] rs1;
    logic      [ 4:0] rs2;
    logic             wb_en;

    // Writeback
    logic      [ 4:0] rd;
    logic      [31:0] pc;

    modport in(
        input reset, enable,
        output alu_result, op_mem, mem_mode, mem_width, rs1, rs2, wb_en, rd, pc
    );
    modport prev(input alu_result, op_mem, mem_mode, mem_width, rs1, rs2, wb_en, rd, pc);
    modport hazard(input rs1, rs2, rd, wb_en, output reset, enable);

endinterface

module stageEX
    import mem_pkg::*;
(
    input                   clk,
          stageEX_face.in   io,
          stageID_face.prev sID
);

    wire [31:0] result;

    alu alu1 (
        .src1    (sID.opA),
        .src2    (sID.opB),
        .operator(sID.alu_op),
        .sub_shar(sID.alu_negb_shar),
        .m_ext   (sID.alu_mul),
        .result
    );

    // --- Pipeline register ---
    always_ff @(posedge clk) begin
        if (io.reset) begin
            io.alu_result <= '0;
            io.op_mem     <= '0;
            io.mem_mode   <= MEM_IDLE;
            io.mem_width  <= WIDTH_32;
            io.rs1        <= '0;
            io.rs2        <= '0;
            io.wb_en      <= '0;
            io.rd         <= '0;
            io.pc         <= '0;
        end else if (io.enable) begin
            io.alu_result <= result;
            io.op_mem     <= sID.op_mem;
            io.mem_mode   <= sID.mem_mode;
            io.mem_width  <= sID.mem_width;
            io.rs1        <= sID.rs1;
            io.rs2        <= sID.rs2;
            io.wb_en      <= sID.wb_en;
            io.rd         <= sID.rd;
            io.pc         <= sID.pc;
        end
    end

endmodule
