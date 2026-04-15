module bsram32
    import mem_pkg::*;
#(
    parameter int BYTES = 4096
) (
    input logic          clk,
    input logic   [31:0] address,
    input logic   [31:0] data_in,
    input width_t        width,
    input logic          write_en,

    output logic [31:0] data_out,
    output logic        error
);

    localparam int DEPTH = BYTES / 4;
    logic   [31:0] memory       [0:DEPTH-1];

    // Internal signals for steering
    logic   [ 1:0] addr_lsb_reg;
    width_t        width_reg;
    logic   [31:0] raw_word;

    // --- 1. Address Decoding & Alignment ---
    logic   [ 3:0] byte_en;
    always_comb begin
        byte_en = 4'b0000;
        unique case (width)
            WIDTH_8:  byte_en = 4'b0001 << address[1:0];
            WIDTH_16: byte_en = address[1] ? 4'b1100 : 4'b0011;
            WIDTH_32: byte_en = 4'b1111;
        endcase
    end

    // --- 2. Synchronous Write & Read Port ---
    always_ff @(posedge clk) begin
        // Perform masked write
        if (write_en) begin
            if (byte_en[0]) memory[address>>2][7:0] <= data_in[7:0];
            if (byte_en[1])
                memory[address>>2][15:8] <= (width == WIDTH_8) ? data_in[7:0] : data_in[15:8];
            if (byte_en[2])
                memory[address>>2][23:16] <= (width == WIDTH_8) ? data_in[7:0] : data_in[23:16];
            if (byte_en[3])
                memory[address>>2][31:24] <= (width == WIDTH_8) ? data_in[7:0] : data_in[31:24];
        end

        // Register signals to sync with the 1-cycle memory latency
        raw_word     <= memory[address>>2];
        addr_lsb_reg <= address[1:0];
        width_reg    <= width;
    end

    // --- 3. Read Steering (Combinational after the Register) ---
    always_comb begin
        case (width_reg)
            WIDTH_8: begin
                unique case (addr_lsb_reg)
                    2'b00: data_out = {24'h0, raw_word[7:0]};
                    2'b01: data_out = {24'h0, raw_word[15:8]};
                    2'b10: data_out = {24'h0, raw_word[23:16]};
                    2'b11: data_out = {24'h0, raw_word[31:24]};
                endcase
            end
            WIDTH_16: begin
                data_out = addr_lsb_reg[1] ? {16'h0, raw_word[31:16]} : {16'h0, raw_word[15:0]};
            end
            WIDTH_32: data_out = raw_word;
            default:  data_out = raw_word;
        endcase
    end

    // Simple error check
    assign error = (width == WIDTH_16 && address[0]) || (width == WIDTH_32 && |address[1:0]);

endmodule
