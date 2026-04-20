interface stageWB_face;
    import mem_pkg::*;

    // Writeback to register file (directly from WB combinational logic)
    logic        write;
    logic [ 4:0] rd;
    logic [31:0] rd_data;

    modport in(output write, rd, rd_data);
    modport id(input write, rd, rd_data);
    modport hazard(input write, rd);

endinterface

module stageWB
    import mem_pkg::*;
(
    input                    clk,
          stageWB_face.in    io,
          stageMEM_face.prev prev
);

    // --- Sign extension on loaded data ---
    logic [31:0] load_data;
    always_comb begin
        load_data = prev.mem_dout;
        if (prev.sign_ext) begin
            case (prev.mem_width)
                WIDTH_8:  load_data = {{24{prev.mem_dout[7]}}, prev.mem_dout[7:0]};
                WIDTH_16: load_data = {{16{prev.mem_dout[15]}}, prev.mem_dout[15:0]};
                WIDTH_32: ;
                default: ;
            endcase
        end
    end

    // --- Writeback mux ---
    assign io.rd_data = prev.is_load ? load_data : prev.alu_result;
    assign io.rd      = prev.rd;
    assign io.write   = prev.wb_en;

endmodule
