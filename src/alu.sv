module alu (
    input [31:0] src1,
    input [31:0] src2,

    input [2:0] operator,
    input sub_shar,
    input m_ext,

    output logic [31:0] result
);

    wire [31:0] src2_oneg = src2 ^ {32{sub_shar}};
    wire signed [31:0] arith_shift = $signed(src1) >>> src2[4:0];

    // m-ext
    wire [63:0] full_mul_uu = src1 * src2;
    wire signed [63:0] full_mul_ss = $signed(src1) * $signed(src2);
    wire signed [63:0] full_mul_su = $signed({src1[31], src1}) * $signed({1'b0, src2});

    always_comb begin
        unique case ({
            m_ext, operator
        })
            {1'b0, 3'b000} : result = src1 + src2_oneg + {31'd0, sub_shar};
            {1'b0, 3'b001} : result = src1 << src2[4:0];
            {1'b0, 3'b010} : result = {31'd0, $signed(src1) < $signed(src2)};
            {1'b0, 3'b011} : result = {31'd0, $unsigned(src1) < $unsigned(src2)};
            {1'b0, 3'b100} : result = src1 ^ src2_oneg;
            {1'b0, 3'b101} : result = sub_shar ? $unsigned(arith_shift) : src1 >> src2[4:0];
            {1'b0, 3'b110} : result = src1 | src2_oneg;
            {1'b0, 3'b111} : result = src1 & src2_oneg;

            {1'b1, 3'b000} : result = full_mul_uu[31:0];  // mul
            {1'b1, 3'b001} : result = full_mul_ss[63:32];  // mulh
            {1'b1, 3'b010} : result = full_mul_su[63:32];  // mulhsu
            {1'b1, 3'b011} : result = full_mul_uu[63:32];  // mulhu
            {1'b1, 3'b100} : result = '0;  // div
            {1'b1, 3'b101} : result = '0;  // divu
            {1'b1, 3'b110} : result = '0;  // mod
            {1'b1, 3'b111} : result = '0;  // modu

        endcase


    end

endmodule

