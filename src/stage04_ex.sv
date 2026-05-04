interface stageEX_face;
    import mem_pkg::*;

    // Pipeline control
    logic             reset;
    logic             stall;
    // Forwarding
    logic             fw_mem;
    logic             fw_wb;

    // ALU result
    logic      [31:0] alu_result;
    logic      [31:0] alu_result_comb;  // combinational (before pipeline reg)

    // Branch (combinational, not registered)
    logic             branch_taken;
    logic      [31:0] branch_target;

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
        input reset, stall,
        output alu_result, alu_result_comb, branch_taken, branch_target,
               op_mem, mem_mode, mem_width, rs1, rs2, wb_en, rd, pc
    );
    modport prev(input alu_result, op_mem, mem_mode, mem_width, rs1, rs2, wb_en, rd, pc);
    modport hazard(input rs1, rs2, rd, wb_en, mem_mode, branch_taken, output reset, stall);

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

    assign io.alu_result_comb = result;

    // --- Branch comparator (combinational) ---
    logic branch_cond;
    always_comb begin
        case (sID.alu_op)
            3'b000:  branch_cond = (sID.opA == sID.opB);  // BEQ
            3'b001:  branch_cond = (sID.opA != sID.opB);  // BNE
            3'b100:  branch_cond = ($signed(sID.opA) < $signed(sID.opB));  // BLT
            3'b101:  branch_cond = !($signed(sID.opA) < $signed(sID.opB));  // BGE
            3'b110:  branch_cond = (sID.opA < sID.opB);  // BLTU
            3'b111:  branch_cond = !(sID.opA < sID.opB);  // BGEU
            default: branch_cond = 1'b0;
        endcase
    end

    assign io.branch_taken  = sID.is_jump || (sID.is_branch && branch_cond);
    assign io.branch_target = sID.branch_target;

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
        end else if (!io.stall) begin
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
