interface stageMEM_face;
    import mem_pkg::*;

    // Pipeline control
    logic          reset;
    logic          enable;

    // Data from memory and ALU (WB selects and sign-extends)
    logic   [31:0] alu_result;
    logic   [31:0] mem_dout;
    logic          is_load;
    logic          sign_ext;
    width_t        mem_width;

    // Writeback
    logic          wb_en;
    logic   [ 4:0] rd;

    modport in(
        input reset, enable,
        output alu_result, mem_dout, is_load, sign_ext, mem_width, wb_en, rd
    );
    modport prev(input alu_result, mem_dout, is_load, sign_ext, mem_width, wb_en, rd);
    modport hazard(input rd, wb_en, is_load, output reset, enable);

endinterface

module stageMEM
    import mem_pkg::*;
(
    input                   clk,
          stageMEM_face.in  io,
          stageEX_face.prev prev
);

    // --- Data memory ---
    logic write_en;
    assign write_en = (prev.mem_mode == MEM_STORE);

    bsram32 #(
        .BYTES(8192)
    ) data_mem (
        .clk,
        .address (prev.alu_result),
        .data_in (prev.op_mem),
        .width   (prev.mem_width),
        .write_en(write_en),
        .data_out(io.mem_dout),
        .error   ()
    );

    // --- Pipeline register (control forwarded for WB) ---
    always_ff @(posedge clk) begin
        if (io.reset) begin
            io.alu_result <= '0;
            io.is_load    <= '0;
            io.sign_ext   <= '0;
            io.mem_width  <= WIDTH_32;
            io.wb_en      <= '0;
            io.rd         <= '0;
        end else if (io.enable) begin
            io.alu_result <= prev.alu_result;
            io.is_load    <= (prev.mem_mode == MEM_LOAD_SIG || prev.mem_mode == MEM_LOAD_USIG);
            io.sign_ext   <= (prev.mem_mode == MEM_LOAD_SIG);
            io.mem_width  <= prev.mem_width;
            io.wb_en      <= prev.wb_en;
            io.rd         <= prev.rd;
        end
    end

endmodule
