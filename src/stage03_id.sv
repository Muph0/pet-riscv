// ID stage I/O
interface stageID_face;
    import mem_pkg::*;

    // Pipeline control
    logic             reset;
    logic             enable;

    // ALU operands
    logic      [31:0] opA;
    logic      [31:0] opB;
    logic      [31:0] op_mem;  // memory write data

    // ALU control
    logic      [ 2:0] alu_op;
    logic             alu_negb_shar;
    logic             alu_mul;

    // Memory control
    mem_mode_t        mem_mode;
    width_t           mem_width;

    // Register tracking
    logic      [ 4:0] rs1;
    logic      [ 4:0] rs2;

    // Writeback
    logic      [ 4:0] rd;
    logic      [31:0] pc;
    logic             wb_en;

    modport in(
        input reset, enable,
        output opA, opB, op_mem, alu_op, alu_negb_shar, alu_mul,
               mem_mode, mem_width, rs1, rs2, wb_en, rd, pc
    );
    modport prev(
        input opA, opB, op_mem, alu_op, alu_negb_shar, alu_mul,
              mem_mode, mem_width, rs1, rs2, wb_en, rd, pc
    );
    modport hazard(input rs1, rs2, rd, wb_en, output reset, enable);

endinterface


// RV32IM opcodes
typedef enum logic [6:0] {
    OP_LUI    = 7'b0110111,
    OP_AUIPC  = 7'b0010111,
    OP_JAL    = 7'b1101111,
    OP_JALR   = 7'b1100111,
    OP_BRANCH = 7'b1100011,
    OP_LOAD   = 7'b0000011,
    OP_STORE  = 7'b0100011,
    OP_IMM    = 7'b0010011,
    OP_REG    = 7'b0110011,
    OP_FENCE  = 7'b0001111,
    OP_SYSTEM = 7'b1110011
} opcode_t;


module stageID
    import mem_pkg::*;
(
    input                   clk,
          stageID_face.in   io,
          stageIF_face.prev prev,
          stageWB_face.id   wb
);

    // --- Instruction field extraction (combinational) ---
    logic [31:0] instr;
    assign instr = prev.instr;

    logic [6:0] opcode;
    logic [4:0] rd;
    logic [2:0] funct3;
    logic [4:0] rs1;
    logic [4:0] rs2;
    logic [6:0] funct7;

    assign opcode = instr[6:0];
    assign rd     = instr[11:7];
    assign funct3 = instr[14:12];
    assign rs1    = instr[19:15];
    assign rs2    = instr[24:20];
    assign funct7 = instr[31:25];

    // --- Immediate generation (combinational) ---
    logic [31:0] imm;
    always_comb begin
        case (opcode_t'(opcode))
            OP_IMM, OP_LOAD, OP_JALR:  // I-type
            imm = {{20{instr[31]}}, instr[31:20]};
            OP_STORE:  // S-type
            imm = {{20{instr[31]}}, instr[31:25], instr[11:7]};
            OP_BRANCH:  // B-type
            imm = {{19{instr[31]}}, instr[31], instr[7], instr[30:25], instr[11:8], 1'b0};
            OP_LUI, OP_AUIPC:  // U-type
            imm = {instr[31:12], 12'b0};
            OP_JAL:  // J-type
            imm = {{11{instr[31]}}, instr[31], instr[19:12], instr[20], instr[30:21], 1'b0};
            OP_REG, OP_SYSTEM, OP_FENCE: imm = '0;
            default: imm = '0;
        endcase
    end

    // --- Register file ---
    logic [31:0] rs1_data, rs2_data;

    regfile regs (
        .clk,
        .write    (wb.write),
        .dest     (wb.rd),
        .dest_data(wb.rd_data),
        .src1     (rs1),
        .src2     (rs2),
        .src1_data(rs1_data),
        .src2_data(rs2_data)
    );

    // --- Control signal generation (combinational) ---
    logic [31:0] opA, opB, op_mem;
    logic      [2:0] alu_op;
    logic            alu_negb_shar;
    logic            alu_mul;
    logic            wb_en;
    mem_mode_t       mem_mode;
    width_t          mem_width;

    always_comb begin
        // Defaults
        opA           = rs1_data;
        opB           = imm;
        op_mem        = rs2_data;
        alu_op        = funct3;
        alu_negb_shar = '0;
        alu_mul       = '0;
        wb_en         = (rd != 5'd0);
        mem_mode      = MEM_IDLE;
        mem_width     = WIDTH_32;

        case (opcode_t'(opcode))
            OP_REG: begin
                opB           = rs2_data;
                alu_negb_shar = funct7[5];  // SUB / SRA
                alu_mul       = funct7[0];  // M-extension
            end
            OP_IMM: begin
                // SRAI: funct7[5] selects arithmetic shift
                if (funct3 == 3'b101) alu_negb_shar = funct7[5];
            end
            OP_LUI: begin
                opA    = '0;
                alu_op = 3'b000;  // ADD 0 + imm
            end
            OP_AUIPC: begin
                opA    = prev.pc;
                alu_op = 3'b000;  // ADD pc + imm
            end
            OP_JAL, OP_JALR: begin
                opA    = prev.pc;
                opB    = 32'd4;
                alu_op = 3'b000;  // ADD pc + 4 (link address)
            end
            OP_LOAD: begin
                alu_op = 3'b000;  // ADD rs1 + imm (address)
                mem_mode = funct3[2] ? MEM_LOAD_USIG : MEM_LOAD_SIG;
                mem_width = width_t'(funct3[1:0]);
            end
            OP_STORE: begin
                alu_op    = 3'b000;  // ADD rs1 + imm (address)
                mem_mode  = MEM_STORE;
                mem_width = funct3[1:0] == 3 ? WIDTH_32 : width_t'(funct3[1:0]);
                wb_en     = '0;
            end
            OP_BRANCH: begin
                opB   = rs2_data;
                wb_en = '0;
            end
            OP_FENCE: begin
                wb_en = '0;
            end
            OP_SYSTEM: begin
                wb_en = '0;
            end
            default: ;
        endcase
    end

    // --- Pipeline register ---
    always_ff @(posedge clk) begin
        if (io.reset) begin
            io.opA           <= '0;
            io.opB           <= '0;
            io.op_mem        <= '0;
            io.alu_op        <= '0;
            io.alu_negb_shar <= '0;
            io.alu_mul       <= '0;
            io.wb_en         <= '0;
            io.mem_mode      <= MEM_IDLE;
            io.mem_width     <= WIDTH_32;
            io.rs1           <= '0;
            io.rs2           <= '0;
            io.rd            <= '0;
            io.pc            <= '0;
        end else if (io.enable) begin
            io.opA           <= opA;
            io.opB           <= opB;
            io.op_mem        <= op_mem;
            io.alu_op        <= alu_op;
            io.alu_negb_shar <= alu_negb_shar;
            io.alu_mul       <= alu_mul;
            io.wb_en         <= wb_en;
            io.mem_mode      <= mem_mode;
            io.mem_width     <= mem_width;
            io.rs1           <= rs1;
            io.rs2           <= rs2;
            io.rd            <= rd;
            io.pc            <= prev.pc;
        end
    end

endmodule
