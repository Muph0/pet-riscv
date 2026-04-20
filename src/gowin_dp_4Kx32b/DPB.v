// =============================================================================
// DPB — Behavioral model of the Gowin DPB (Dual-Port Block RAM) primitive
//
// For simulation only.  Models the subset of DPB functionality used by
// Gowin IP Generator output (specifically Gowin_DP_4Kx32b).
//
// Reference: Gowin UG285E — BSRAM & SSRAM User Guide
//
// Key behaviors modeled:
//   - True dual-port RAM, one read/write port per side (A and B)
//   - Configurable data width per port via BIT_WIDTH_0 / BIT_WIDTH_1
//   - BLKSEL gating (port is active only when BLKSEL matches)
//   - WRITE_MODE: 00 = read-before-write, 01 = read-after-write, 10 = no-read-on-write
//   - READ_MODE:  0 = bypass (no output register), 1 = pipeline (extra output register)
//   - Synchronous reset (active-high RESETA / RESETB clears output to 0)
//   - CE gating (port idle when CE deasserted)
//   - OCE gates the output register in pipeline mode
// =============================================================================

module DPB (
    output reg [15:0] DOA,
    output reg [15:0] DOB,

    input        CLKA,
    input        OCEA,
    input        CEA,
    input        RESETA,
    input        WREA,

    input        CLKB,
    input        OCEB,
    input        CEB,
    input        RESETB,
    input        WREB,

    input  [2:0] BLKSELA,
    input  [2:0] BLKSELB,

    input [13:0] ADA,
    input [15:0] DIA,

    input [13:0] ADB,
    input [15:0] DIB
);

    // Parameters (set via defparam in the generated wrapper)
    parameter [0:0]  READ_MODE0  = 1'b0;   // 0 = bypass, 1 = pipeline
    parameter [0:0]  READ_MODE1  = 1'b0;
    parameter [1:0]  WRITE_MODE0 = 2'b00;  // 00 = read-before-write
    parameter [1:0]  WRITE_MODE1 = 2'b00;  // 01 = read-after-write, 10 = no-change
    parameter        BIT_WIDTH_0 = 16;
    parameter        BIT_WIDTH_1 = 16;
    parameter [2:0]  BLK_SEL_0   = 3'b000;
    parameter [2:0]  BLK_SEL_1   = 3'b000;
    parameter        RESET_MODE  = "SYNC";

    // Memory initialization (optional, for preloading via readmemh etc.)
    parameter [255:0] INIT_RAM_00 = 256'h0;
    parameter [255:0] INIT_RAM_01 = 256'h0;
    parameter [255:0] INIT_RAM_02 = 256'h0;
    parameter [255:0] INIT_RAM_03 = 256'h0;
    parameter [255:0] INIT_RAM_04 = 256'h0;
    parameter [255:0] INIT_RAM_05 = 256'h0;
    parameter [255:0] INIT_RAM_06 = 256'h0;
    parameter [255:0] INIT_RAM_07 = 256'h0;
    parameter [255:0] INIT_RAM_08 = 256'h0;
    parameter [255:0] INIT_RAM_09 = 256'h0;
    parameter [255:0] INIT_RAM_0A = 256'h0;
    parameter [255:0] INIT_RAM_0B = 256'h0;
    parameter [255:0] INIT_RAM_0C = 256'h0;
    parameter [255:0] INIT_RAM_0D = 256'h0;
    parameter [255:0] INIT_RAM_0E = 256'h0;
    parameter [255:0] INIT_RAM_0F = 256'h0;
    parameter [255:0] INIT_RAM_10 = 256'h0;
    parameter [255:0] INIT_RAM_11 = 256'h0;
    parameter [255:0] INIT_RAM_12 = 256'h0;
    parameter [255:0] INIT_RAM_13 = 256'h0;
    parameter [255:0] INIT_RAM_14 = 256'h0;
    parameter [255:0] INIT_RAM_15 = 256'h0;
    parameter [255:0] INIT_RAM_16 = 256'h0;
    parameter [255:0] INIT_RAM_17 = 256'h0;
    parameter [255:0] INIT_RAM_18 = 256'h0;
    parameter [255:0] INIT_RAM_19 = 256'h0;
    parameter [255:0] INIT_RAM_1A = 256'h0;
    parameter [255:0] INIT_RAM_1B = 256'h0;
    parameter [255:0] INIT_RAM_1C = 256'h0;
    parameter [255:0] INIT_RAM_1D = 256'h0;
    parameter [255:0] INIT_RAM_1E = 256'h0;
    parameter [255:0] INIT_RAM_1F = 256'h0;
    parameter [255:0] INIT_RAM_20 = 256'h0;
    parameter [255:0] INIT_RAM_21 = 256'h0;
    parameter [255:0] INIT_RAM_22 = 256'h0;
    parameter [255:0] INIT_RAM_23 = 256'h0;
    parameter [255:0] INIT_RAM_24 = 256'h0;
    parameter [255:0] INIT_RAM_25 = 256'h0;
    parameter [255:0] INIT_RAM_26 = 256'h0;
    parameter [255:0] INIT_RAM_27 = 256'h0;
    parameter [255:0] INIT_RAM_28 = 256'h0;
    parameter [255:0] INIT_RAM_29 = 256'h0;
    parameter [255:0] INIT_RAM_2A = 256'h0;
    parameter [255:0] INIT_RAM_2B = 256'h0;
    parameter [255:0] INIT_RAM_2C = 256'h0;
    parameter [255:0] INIT_RAM_2D = 256'h0;
    parameter [255:0] INIT_RAM_2E = 256'h0;
    parameter [255:0] INIT_RAM_2F = 256'h0;
    parameter [255:0] INIT_RAM_30 = 256'h0;
    parameter [255:0] INIT_RAM_31 = 256'h0;
    parameter [255:0] INIT_RAM_32 = 256'h0;
    parameter [255:0] INIT_RAM_33 = 256'h0;
    parameter [255:0] INIT_RAM_34 = 256'h0;
    parameter [255:0] INIT_RAM_35 = 256'h0;
    parameter [255:0] INIT_RAM_36 = 256'h0;
    parameter [255:0] INIT_RAM_37 = 256'h0;
    parameter [255:0] INIT_RAM_38 = 256'h0;
    parameter [255:0] INIT_RAM_39 = 256'h0;
    parameter [255:0] INIT_RAM_3A = 256'h0;
    parameter [255:0] INIT_RAM_3B = 256'h0;
    parameter [255:0] INIT_RAM_3C = 256'h0;
    parameter [255:0] INIT_RAM_3D = 256'h0;
    parameter [255:0] INIT_RAM_3E = 256'h0;
    parameter [255:0] INIT_RAM_3F = 256'h0;

    // -----------------------------------------------------------------------
    // Underlying storage — 16K bits organized as 16384 x 1
    // -----------------------------------------------------------------------
    reg mem [0:16383];

    integer _i;
    initial begin
        for (_i = 0; _i < 16384; _i = _i + 1) mem[_i] = 1'b0;
    end

    // -----------------------------------------------------------------------
    // Address & data helpers — width-dependent slicing
    //
    // DPB address mapping (from UG285E Table 3-4):
    //   BIT_WIDTH  Addr bits   Data bits   Depth
    //   1          AD[13:0]    DI[0]       16384
    //   2          AD[13:1]    DI[1:0]     8192
    //   4          AD[13:2]    DI[3:0]     4096
    //   8          AD[13:3]    DI[7:0]     2048
    //   16         AD[13:4]    DI[15:0]    1024
    // -----------------------------------------------------------------------
    function integer addr_bits;
        input integer bw;
        case (bw)
            1:  addr_bits = 14;
            2:  addr_bits = 13;
            4:  addr_bits = 12;
            8:  addr_bits = 11;
            16: addr_bits = 10;
            default: addr_bits = 14;
        endcase
    endfunction

    // -----------------------------------------------------------------------
    // Port A
    // -----------------------------------------------------------------------
    wire        sel_a   = (BLKSELA == BLK_SEL_0);
    wire        act_a   = CEA & sel_a;
    reg  [15:0] rdata_a;
    reg  [15:0] pipe_a;

    // Address → flat bit index
    function [13:0] flat_addr_a;
        input [13:0] ad;
        case (BIT_WIDTH_0)
            1:  flat_addr_a = ad;
            2:  flat_addr_a = {ad[13:1], 1'b0};
            4:  flat_addr_a = {ad[13:2], 2'b0};
            8:  flat_addr_a = {ad[13:3], 3'b0};
            16: flat_addr_a = {ad[13:4], 4'b0};
            default: flat_addr_a = ad;
        endcase
    endfunction

    always @(posedge CLKA) begin
        if (RESETA) begin
            rdata_a <= 16'b0;
            if (READ_MODE0) pipe_a <= 16'b0;
        end else if (act_a) begin
            // Capture old data before write (for read-before-write)
            for (_i = 0; _i < 16; _i = _i + 1)
                if (_i < BIT_WIDTH_0) rdata_a[_i] <= mem[flat_addr_a(ADA) + _i];
                else                  rdata_a[_i] <= 1'b0;

            // Write
            if (WREA)
                for (_i = 0; _i < BIT_WIDTH_0; _i = _i + 1)
                    mem[flat_addr_a(ADA) + _i] <= DIA[_i];

            // For read-after-write, override with new data
            if (WREA && WRITE_MODE0 == 2'b01)
                for (_i = 0; _i < BIT_WIDTH_0; _i = _i + 1)
                    rdata_a[_i] <= DIA[_i];

            // For no-change-on-write, don't update read output
            if (WREA && WRITE_MODE0 == 2'b10)
                for (_i = 0; _i < 16; _i = _i + 1)
                    rdata_a[_i] <= rdata_a[_i]; // hold
        end
        // Pipeline register
        if (READ_MODE0 && (OCEA || RESETA))
            pipe_a <= RESETA ? 16'b0 : rdata_a;
    end

    always @(*) begin
        if (READ_MODE0)
            DOA = pipe_a;
        else
            DOA = rdata_a;
    end

    // -----------------------------------------------------------------------
    // Port B
    // -----------------------------------------------------------------------
    wire        sel_b   = (BLKSELB == BLK_SEL_1);
    wire        act_b   = CEB & sel_b;
    reg  [15:0] rdata_b;
    reg  [15:0] pipe_b;

    function [13:0] flat_addr_b;
        input [13:0] ad;
        case (BIT_WIDTH_1)
            1:  flat_addr_b = ad;
            2:  flat_addr_b = {ad[13:1], 1'b0};
            4:  flat_addr_b = {ad[13:2], 2'b0};
            8:  flat_addr_b = {ad[13:3], 3'b0};
            16: flat_addr_b = {ad[13:4], 4'b0};
            default: flat_addr_b = ad;
        endcase
    endfunction

    always @(posedge CLKB) begin
        if (RESETB) begin
            rdata_b <= 16'b0;
            if (READ_MODE1) pipe_b <= 16'b0;
        end else if (act_b) begin
            for (_i = 0; _i < 16; _i = _i + 1)
                if (_i < BIT_WIDTH_1) rdata_b[_i] <= mem[flat_addr_b(ADB) + _i];
                else                  rdata_b[_i] <= 1'b0;

            if (WREB)
                for (_i = 0; _i < BIT_WIDTH_1; _i = _i + 1)
                    mem[flat_addr_b(ADB) + _i] <= DIB[_i];

            if (WREB && WRITE_MODE1 == 2'b01)
                for (_i = 0; _i < BIT_WIDTH_1; _i = _i + 1)
                    rdata_b[_i] <= DIB[_i];

            if (WREB && WRITE_MODE1 == 2'b10)
                for (_i = 0; _i < 16; _i = _i + 1)
                    rdata_b[_i] <= rdata_b[_i];
        end
        if (READ_MODE1 && (OCEB || RESETB))
            pipe_b <= RESETB ? 16'b0 : rdata_b;
    end

    always @(*) begin
        if (READ_MODE1)
            DOB = pipe_b;
        else
            DOB = rdata_b;
    end

endmodule
