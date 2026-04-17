// Parametrized Wishbone B4 classic-cycle slave memory
// 1-wait-state: ACK is asserted one cycle after STB.
// Optional bootloader byte-write port for direct memory loading.
module wb_bsram #(
    parameter int BYTES = 4096
) (
    wishbone.slave bus,

    // Bootloader byte-write port (active independently of bus)
    input logic [31:0] bl_addr,
    input logic [ 7:0] bl_data,
    input logic        bl_write
);

    localparam int DEPTH = BYTES / 4;
    logic [31:0] memory[0:DEPTH-1];

    // synthesis translate_off
    initial for (int i = 0; i < DEPTH; i++) memory[i] = '0;
    // synthesis translate_on

    // Word address from bus (use lower bits — base offset handled by crossbar routing)
    logic [$clog2(DEPTH)-1:0] word_addr;
    assign word_addr = bus.adr[$clog2(BYTES)-1:2];

    // Registered ack — 1-wait-state classic Wishbone
    logic ack_r;

    always_ff @(posedge bus.clk) begin
        if (bus.reset) begin
            ack_r <= 1'b0;
        end else begin
            ack_r <= bus.cyc && bus.stb && !ack_r;

            // Wishbone byte-enable write
            if (bus.cyc && bus.stb && bus.we && !ack_r) begin
                if (bus.sel[0]) memory[word_addr][7:0] <= bus.mtos[7:0];
                if (bus.sel[1]) memory[word_addr][15:8] <= bus.mtos[15:8];
                if (bus.sel[2]) memory[word_addr][23:16] <= bus.mtos[23:16];
                if (bus.sel[3]) memory[word_addr][31:24] <= bus.mtos[31:24];
            end
        end

        // Bootloader byte write — always active, independent of bus reset
        if (bl_write) begin
            case (bl_addr[1:0])
                2'b00: memory[bl_addr[$clog2(BYTES)-1:2]][7:0] <= bl_data;
                2'b01: memory[bl_addr[$clog2(BYTES)-1:2]][15:8] <= bl_data;
                2'b10: memory[bl_addr[$clog2(BYTES)-1:2]][23:16] <= bl_data;
                2'b11: memory[bl_addr[$clog2(BYTES)-1:2]][31:24] <= bl_data;
            endcase
        end
    end

    // Synchronous read — data valid on the cycle ack is asserted
    logic [31:0] rdata_r;
    always_ff @(posedge bus.clk) begin
        rdata_r <= memory[word_addr];
    end

    assign bus.stom = rdata_r;
    assign bus.ack  = ack_r;
    assign bus.err  = 1'b0;
    assign bus.rty  = 1'b0;

endmodule
