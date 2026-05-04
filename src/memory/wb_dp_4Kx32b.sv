// =============================================================================
// Dual-port Wishbone wrapper around Gowin_DP_4Kx32b (4096 x 32-bit BSRAM)
//
// Exposes two independent Wishbone B4 classic-cycle slave ports (A and B),
// each mapped to one port of the underlying dual-port block RAM.
//
// Port A additionally has a bootloader byte-write interface for direct
// memory loading before the CPU starts.
//
// The Gowin IP has no byte-enable pins — it writes full 32-bit words.
// Port A (IROM) is read-only from the bus side, so no byte-enable issue.
// Port B (SRAM) supports byte-enable writes via read-modify-write:
//   - Full-word writes (sel==4'hF): 1 wait state (same as reads)
//   - Partial writes (sel!=4'hF):   2 wait states (read + merge-write)
//
// The Gowin IP operates with READ_MODE=0 (bypass, 1-cycle read latency).
// =============================================================================
module wb_dp_4Kx32b (
    wishbone.slave bus_a,
    wishbone.slave bus_b,

    // Bootloader byte-write port (directly writes port A side)
    input logic [31:0] bl_addr,
    input logic [ 7:0] bl_data,
    input logic        bl_write
);

    localparam int DEPTH = 4096;  // 4K words × 32 bits = 16 KB

    wire         clk = bus_a.clk;
    wire         reset = bus_a.reset;

    // -------------------------------------------------------------------------
    // Bootloader byte→word conversion
    //
    // The Gowin IP only supports full-word writes (no byte enables).
    // The bootloader sends one byte at a time. We accumulate 4 bytes into a
    // 32-bit register and write the full word once we have all 4 bytes.
    // -------------------------------------------------------------------------
    logic [31:0] bl_word;
    logic [31:0] bl_word_addr;
    logic        bl_word_wr;

    always_ff @(posedge clk) begin
        bl_word_wr <= 1'b0;
        if (bl_write) begin
            case (bl_addr[1:0])
                2'b00: bl_word[7:0] <= bl_data;
                2'b01: bl_word[15:8] <= bl_data;
                2'b10: bl_word[23:16] <= bl_data;
                2'b11: begin
                    bl_word[31:24] <= bl_data;
                    bl_word_wr     <= 1'b1;
                    bl_word_addr   <= {bl_addr[31:2], 2'b00};
                end
            endcase
        end
    end

    // -------------------------------------------------------------------------
    // Port A — IROM (read-only from bus, full-word writes from bootloader)
    // -------------------------------------------------------------------------
    wire         wb_a_active = bus_a.cyc & bus_a.stb;
    logic        ack_a;
    wire  [11:0] addr_a;
    wire  [31:0] din_a;
    wire         wre_a;
    wire         ce_a;
    wire  [31:0] dout_a;

    assign addr_a = bl_word_wr ? bl_word_addr[13:2] : bus_a.adr[13:2];
    assign din_a  = bl_word_wr ? bl_word : bus_a.mtos;
    assign wre_a  = bl_word_wr;  // Bus side is read-only
    assign ce_a   = bl_word_wr | wb_a_active;

    always_ff @(posedge clk) begin
        if (reset) ack_a <= 1'b0;
        else ack_a <= wb_a_active & ~ack_a & ~bl_word_wr;
    end

    assign bus_a.ack  = ack_a;
    assign bus_a.err  = 1'b0;
    assign bus_a.rty  = 1'b0;
    assign bus_a.stom = dout_a;

    // -------------------------------------------------------------------------
    // Port B — SRAM (read/write with byte enables via read-modify-write)
    //
    // Full-word writes (sel==4'hF) complete in 1 wait state.
    // Partial writes (sel!=4'hF) need 2 wait states:
    //   Cycle 0: Bus request arrives, start read  (ce=1, wre=0)
    //   Cycle 1: doutb has old word. Merge bytes,  start write (ce=1, wre=1)
    //            Assert ACK.
    // -------------------------------------------------------------------------
    wire         wb_b_active = bus_b.cyc & bus_b.stb;
    logic        ack_b;
    logic [11:0] addr_b;
    logic [31:0] din_b;
    logic        wre_b;
    logic        ce_b;
    wire  [31:0] dout_b;

    wire         b_is_write = wb_b_active & bus_b.we;
    wire         b_full_word = (bus_b.sel == 4'hF);
    wire         b_partial = b_is_write & ~b_full_word;

    // RMW state: 0 = idle/normal, 1 = read phase done, do merge-write
    logic        rmw_phase;

    // Merged write data: old word with selected bytes replaced
    logic [31:0] merged_data;
    always_comb begin
        merged_data = dout_b;
        if (bus_b.sel[0]) merged_data[7:0] = bus_b.mtos[7:0];
        if (bus_b.sel[1]) merged_data[15:8] = bus_b.mtos[15:8];
        if (bus_b.sel[2]) merged_data[23:16] = bus_b.mtos[23:16];
        if (bus_b.sel[3]) merged_data[31:24] = bus_b.mtos[31:24];
    end

    always_comb begin
        if (rmw_phase) begin
            // Merge-write phase: write merged data, same address
            addr_b = bus_b.adr[13:2];
            din_b  = merged_data;
            wre_b  = 1'b1;
            ce_b   = 1'b1;
        end else if (b_partial & ~ack_b) begin
            // Partial write, read phase: issue read to get old data
            addr_b = bus_b.adr[13:2];
            din_b  = '0;
            wre_b  = 1'b0;
            ce_b   = 1'b1;
        end else begin
            // Normal operation: reads, full-word writes
            addr_b = bus_b.adr[13:2];
            din_b  = bus_b.mtos;
            wre_b  = b_is_write & b_full_word & ~ack_b;
            ce_b   = wb_b_active;
        end
    end

    always_ff @(posedge clk) begin
        if (reset) begin
            ack_b     <= 1'b0;
            rmw_phase <= 1'b0;
        end else begin
            ack_b     <= 1'b0;
            rmw_phase <= 1'b0;

            if (rmw_phase) begin
                // Merge-write committed this cycle, ACK
                ack_b <= 1'b1;
            end else if (b_partial & ~ack_b) begin
                // Read phase done next cycle — advance to merge-write
                rmw_phase <= 1'b1;
            end else if (wb_b_active & ~ack_b) begin
                // Normal read or full-word write — 1-wait-state ACK
                ack_b <= 1'b1;
            end
        end
    end

    assign bus_b.ack  = ack_b;
    assign bus_b.err  = 1'b0;
    assign bus_b.rty  = 1'b0;
    assign bus_b.stom = dout_b;

    // -------------------------------------------------------------------------
    // Gowin dual-port BSRAM instance
    // -------------------------------------------------------------------------
    Gowin_DP_4Kx32b ram (
        .clka  (clk),
        .ocea  (1'b1),
        .cea   (ce_a),
        .reseta(reset),
        .wrea  (wre_a),
        .ada   (addr_a),
        .dina  (din_a),
        .douta (dout_a),

        .clkb  (clk),
        .oceb  (1'b1),
        .ceb   (ce_b),
        .resetb(reset),
        .wreb  (wre_b),
        .adb   (addr_b),
        .dinb  (din_b),
        .doutb (dout_b)
    );

endmodule
