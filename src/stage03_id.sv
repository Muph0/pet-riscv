// ID stage I/O
interface id_stage_io;

    logic        reset;

    // Pipeline control
    logic        stall;

    // Decoded fields
    logic [ 6:0] opcode;
    logic [ 4:0] rd;
    logic [ 2:0] funct3;
    logic [ 4:0] rs1;
    logic [ 4:0] rs2;
    logic [ 6:0] funct7;
    logic [31:0] imm;
    logic [31:0] pc;

    // Register file read data
    logic [31:0] rs1_data;
    logic [31:0] rs2_data;

    modport in(
        input reset, stall,
        output opcode, rd, funct3, rs1, rs2, funct7, imm, pc, rs1_data, rs2_data
    );
    modport prev(input opcode, rd, funct3, rs1, rs2, funct7, imm, pc, rs1_data, rs2_data);

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


module id_stage (
    input                  clk,
          id_stage_io.in   io,
          if_stage_io.prev prev
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
    regfile regs (
        .clk,
        .write    ('0),           // TODO: connect from WB stage
        .dest     ('0),
        .dest_data('0),
        .src1     (rs1),
        .src2     (rs2),
        .src1_data(io.rs1_data),
        .src2_data(io.rs2_data)
    );

    // --- Pipeline register ---
    always_ff @(posedge clk) begin
        if (io.reset) begin
            io.opcode <= '0;
            io.rd     <= '0;
            io.funct3 <= '0;
            io.rs1    <= '0;
            io.rs2    <= '0;
            io.funct7 <= '0;
            io.imm    <= '0;
            io.pc     <= '0;
        end else if (!io.stall) begin
            io.opcode <= opcode;
            io.rd     <= rd;
            io.funct3 <= funct3;
            io.rs1    <= rs1;
            io.rs2    <= rs2;
            io.funct7 <= funct7;
            io.imm    <= imm;
            io.pc     <= prev.pc;
        end
    end

endmodule
