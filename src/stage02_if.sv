// IF stage I/O
interface if_stage_io;

    logic        reset;

    // Pipeline control
    logic        stall;
    logic        loading;  // high while bootloader owns memory

    // Bootloader memory write port
    logic [31:0] bl_addr;
    logic [ 7:0] bl_data;
    logic        bl_write;

    // To next stage
    logic [31:0] instr;  // fetched instruction
    logic [31:0] pc;  // PC associated with fetched instruction

    modport in(input reset, stall, loading, bl_addr, bl_data, bl_write, output instr, pc);
    modport prev(input instr, pc);  // "prev" as seen by the next stage

endinterface


module if_stage
    import mem_pkg::*;
(
    input                  clk,
          if_stage_io.in   io,
          pc_stage_io.prev prev
);

    // BSRAM port mux signals
    logic   [31:0] mem_address;
    logic   [31:0] mem_data_in;
    width_t        mem_width;
    logic          mem_write_en;

    always_comb begin
        if (io.loading) begin
            mem_address  = io.bl_addr;
            mem_data_in  = {24'b0, io.bl_data};
            mem_width    = WIDTH_8;
            mem_write_en = io.bl_write;
        end else begin
            mem_address  = prev.pc;
            mem_data_in  = '0;
            mem_width    = WIDTH_32;
            mem_write_en = '0;
        end
    end

    // --- Pipeline register: delay PC to match BSRAM latency ---
    always_ff @(posedge clk) begin
        if (io.reset) io.pc <= '0;
        else if (!io.stall && !io.loading) io.pc <= prev.pc;
    end

    // --- Instruction memory ---
    bsram32 #(
        .BYTES(8192)
    ) instr_mem (
        .clk     (clk),
        .address (mem_address),
        .data_in (mem_data_in),
        .width   (mem_width),
        .write_en(mem_write_en),
        .data_out(io.instr),
        .error   ()
    );

endmodule
