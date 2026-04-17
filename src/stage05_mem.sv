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

    // Wishbone stall (bus response takes >1 cycle)
    logic          wb_stall;

    modport in(
        input reset, enable,
        output alu_result, mem_dout, is_load, sign_ext, mem_width, wb_en, rd, wb_stall
    );
    modport prev(input alu_result, mem_dout, is_load, sign_ext, mem_width, wb_en, rd);
    modport hazard(input rd, wb_en, is_load, wb_stall, output reset, enable);

endinterface

module stageMEM
    import mem_pkg::*;
(
    input                   clk,
          stageMEM_face.in  io,
          stageEX_face.prev prev,
          wishbone.master   dbus
);

    // --- Memory operation detection ---
    logic mem_active;
    assign mem_active = (prev.mem_mode != MEM_IDLE);

    logic write_en;
    assign write_en = (prev.mem_mode == MEM_STORE);

    // --- Got-ack tracking (prevent re-issuing completed transactions) ---
    logic got_ack;
    always_ff @(posedge clk) begin
        if (io.reset || io.enable) got_ack <= 1'b0;
        else if (dbus.ack || dbus.err) got_ack <= 1'b1;
    end

    // --- Drive data bus ---
    assign dbus.adr = prev.alu_result;
    assign dbus.we  = write_en;
    assign dbus.cyc = mem_active && !got_ack;
    assign dbus.stb = mem_active && !got_ack;

    // Write data and byte-select steering
    always_comb begin
        dbus.mtos = '0;
        dbus.sel  = 4'b0000;
        case (prev.mem_width)
            WIDTH_8: begin
                dbus.mtos = {4{prev.op_mem[7:0]}};
                dbus.sel  = 4'b0001 << prev.alu_result[1:0];
            end
            WIDTH_16: begin
                dbus.mtos = {2{prev.op_mem[15:0]}};
                dbus.sel  = prev.alu_result[1] ? 4'b1100 : 4'b0011;
            end
            WIDTH_32: begin
                dbus.mtos = prev.op_mem;
                dbus.sel  = 4'b1111;
            end
            default: begin
                dbus.mtos = prev.op_mem;
                dbus.sel  = 4'b1111;
            end
        endcase
    end

    // --- Read data steering (combinational helper) ---
    logic [31:0] steered_rdata;
    always_comb begin
        case (prev.mem_width)
            WIDTH_8: begin
                unique case (prev.alu_result[1:0])
                    2'b00: steered_rdata = {24'h0, dbus.stom[7:0]};
                    2'b01: steered_rdata = {24'h0, dbus.stom[15:8]};
                    2'b10: steered_rdata = {24'h0, dbus.stom[23:16]};
                    2'b11: steered_rdata = {24'h0, dbus.stom[31:24]};
                endcase
            end
            WIDTH_16: begin
                steered_rdata = prev.alu_result[1]
                    ? {16'h0, dbus.stom[31:16]}
                    : {16'h0, dbus.stom[15:0]};
            end
            WIDTH_32: steered_rdata = dbus.stom;
            default:  steered_rdata = dbus.stom;
        endcase
    end

    // --- Pipeline register (control + data forwarded for WB) ---
    // mem_dout is registered here (captured on enable, when ack has just
    // arrived) so that WB sees stable data after the pipeline advances.
    always_ff @(posedge clk) begin
        if (io.reset) begin
            io.alu_result <= '0;
            io.mem_dout   <= '0;
            io.is_load    <= '0;
            io.sign_ext   <= '0;
            io.mem_width  <= WIDTH_32;
            io.wb_en      <= '0;
            io.rd         <= '0;
        end else if (io.enable) begin
            io.alu_result <= prev.alu_result;
            io.mem_dout   <= steered_rdata;
            io.is_load    <= (prev.mem_mode == MEM_LOAD_SIG || prev.mem_mode == MEM_LOAD_USIG);
            io.sign_ext   <= (prev.mem_mode == MEM_LOAD_SIG);
            io.mem_width  <= prev.mem_width;
            io.wb_en      <= prev.wb_en;
            io.rd         <= prev.rd;
        end
    end

    // --- Wishbone stall ---
    // Stall while a memory bus transaction is in progress and hasn't completed.
    assign io.wb_stall = dbus.cyc && dbus.stb && !(dbus.ack || dbus.err);

endmodule
