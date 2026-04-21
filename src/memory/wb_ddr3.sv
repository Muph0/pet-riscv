module wb_ddr3 (
    input clk,  // 27MHz clock for rPLL
    wishbone.slave bus,
    
    output logic [1:0] ddr_status, // bit 1: busy, bit 0: init_calib_complete

    // DDR3 Pins
    output logic [14-1:0] O_ddr_addr,
    output logic [ 3-1:0] O_ddr_ba,
    output logic          O_ddr_cs_n,
    output logic          O_ddr_ras_n,
    output logic          O_ddr_cas_n,
    output logic          O_ddr_we_n,
    output logic          O_ddr_clk,
    output logic          O_ddr_clk_n,
    output logic          O_ddr_cke,
    output logic          O_ddr_odt,
    output logic          O_ddr_reset_n,
    output logic [ 2-1:0] O_ddr_dqm,
    inout  logic [16-1:0] IO_ddr_dq,
    inout  logic [ 2-1:0] IO_ddr_dqs,
    inout  logic [ 2-1:0] IO_ddr_dqs_n
);

    wire memory_clk, pll_lock;
    wire rst_n = ~bus.reset;  // from wishbone bus

    // rPLL instance
    Gowin_rPLL pll (
        .clkout(memory_clk),
        .lock  (pll_lock),
        .reset (~rst_n),
        .clkin (clk)
    );

    // App Interface
    wire [  5:0] app_burst_number = 0;  // single burst of 128 bits
    reg          app_cmd_en;
    reg  [  2:0] app_cmd;
    wire         app_cmd_rdy;

    wire [ 27:0] app_addr;  // 28 bits

    reg          app_wren;
    wire         app_data_end = 1'b1;
    reg  [127:0] app_data;
    wire         app_data_rdy;
    reg  [ 15:0] app_data_mask;

    wire [127:0] app_rdata;
    wire         app_rdata_valid;
    wire         app_rdata_end;
    wire         init_calib_complete;
    wire         clk_out;  // Controller user clock

    DDR3_Memory_Interface_Top u_ddr3 (
        .clk                (clk),
        .memory_clk         (memory_clk),
        .pll_lock           (pll_lock),
        .rst_n              (rst_n),
        .app_burst_number   (app_burst_number),
        .cmd_ready          (app_cmd_rdy),
        .cmd                (app_cmd),
        .cmd_en             (app_cmd_en),
        .addr               (app_addr),
        .wr_data_rdy        (app_data_rdy),
        .wr_data            (app_data),
        .wr_data_en         (app_wren),
        .wr_data_end        (app_data_end),
        .wr_data_mask       (app_data_mask),
        .rd_data            (app_rdata),
        .rd_data_valid      (app_rdata_valid),
        .rd_data_end        (app_rdata_end),
        .sr_req             (1'b0),
        .ref_req            (1'b0),
        .sr_ack             (),
        .ref_ack            (),
        .init_calib_complete(init_calib_complete),
        .clk_out            (clk_out),
        .burst              (1'b0),
        .ddr_rst            (),
        .O_ddr_addr         (O_ddr_addr),
        .O_ddr_ba           (O_ddr_ba),
        .O_ddr_cs_n         (O_ddr_cs_n),
        .O_ddr_ras_n        (O_ddr_ras_n),
        .O_ddr_cas_n        (O_ddr_cas_n),
        .O_ddr_we_n         (O_ddr_we_n),
        .O_ddr_clk          (O_ddr_clk),
        .O_ddr_clk_n        (O_ddr_clk_n),
        .O_ddr_cke          (O_ddr_cke),
        .O_ddr_odt          (O_ddr_odt),
        .O_ddr_reset_n      (O_ddr_reset_n),
        .O_ddr_dqm          (O_ddr_dqm),
        .IO_ddr_dq          (IO_ddr_dq),
        .IO_ddr_dqs         (IO_ddr_dqs),
        .IO_ddr_dqs_n       (IO_ddr_dqs_n)
    );

    // =========================================================================
    // Wishbone to App Interface Wait-State Cross-Domain Sync
    // =========================================================================

    // Sync bus.stb to clk_out
    reg stb_sync1, stb_sync2;
    always_ff @(posedge clk_out) begin
        if (!rst_n) begin
            stb_sync1 <= 1'b0;
            stb_sync2 <= 1'b0;
        end else begin
            stb_sync1 <= bus.stb && bus.cyc;
            stb_sync2 <= stb_sync1;
        end
    end

    reg [2:0] state;
    localparam S_IDLE = 0, S_CMD_WRITE = 1, S_WAIT_WRITE = 2, S_CMD_READ = 3, S_WAIT_READ = 4, S_DONE = 5;

    // Determine target DDR block address for app_addr
    // Byte address is bus.adr (32-bit). A 128-bit block is 16 bytes.
    // Address increments by 8 for every 16 bytes (because it's a half-word address internally by Gowin).
    // So byte_addr / 2 gives the half word addr.
    // However, it must be aligned to 16 bytes (8 half-words), meaning bottom 3 bits of app_addr are 0.
    wire [27:0] target_app_addr = {1'b0, bus.adr[27:4], 3'b000};
    assign app_addr = target_app_addr;

    wire [1:0] word_sel = bus.adr[3:2];

    always_comb begin
        app_data_mask = 16'hFFFF;
        case (word_sel)
            2'b00: app_data_mask[3:0] = ~bus.sel;
            2'b01: app_data_mask[7:4] = ~bus.sel;
            2'b10: app_data_mask[11:8] = ~bus.sel;
            2'b11: app_data_mask[15:12] = ~bus.sel;
        endcase
    end

    reg        transaction_done;
    reg [31:0] latched_rdata;

    always_ff @(posedge clk_out) begin
        if (!rst_n || !init_calib_complete) begin
            state <= S_IDLE;
            app_cmd_en <= 1'b0;
            app_wren <= 1'b0;
            transaction_done <= 1'b0;
        end else begin
            case (state)
                S_IDLE: begin
                    app_cmd_en <= 1'b0;
                    app_wren   <= 1'b0;
                    if (stb_sync2 && !transaction_done) begin
                        if (bus.we) begin
                            app_data <= {4{bus.mtos}};
                            state <= S_CMD_WRITE;
                        end else begin
                            state <= S_CMD_READ;
                        end
                    end
                    if (!stb_sync2) begin
                        transaction_done <= 1'b0;
                    end
                end

                S_CMD_WRITE: begin
                    if (app_cmd_rdy && app_data_rdy) begin
                        app_cmd_en <= 1'b1;
                        app_cmd <= 3'd0;  // Write
                        app_wren <= 1'b1;
                        state <= S_WAIT_WRITE;
                    end
                end

                S_WAIT_WRITE: begin
                    app_cmd_en <= 1'b0;
                    app_wren <= 1'b0;
                    transaction_done <= 1'b1;
                    state <= S_DONE;
                end

                S_CMD_READ: begin
                    if (app_cmd_rdy) begin
                        app_cmd_en <= 1'b1;
                        app_cmd <= 3'd1;  // Read
                        state <= S_WAIT_READ;
                    end
                end

                S_WAIT_READ: begin
                    app_cmd_en <= 1'b0;
                    if (app_rdata_valid) begin
                        case (word_sel)
                            2'b00: latched_rdata <= app_rdata[31:0];
                            2'b01: latched_rdata <= app_rdata[63:32];
                            2'b10: latched_rdata <= app_rdata[95:64];
                            2'b11: latched_rdata <= app_rdata[127:96];
                        endcase
                        transaction_done <= 1'b1;
                        state <= S_DONE;
                    end
                end

                S_DONE: begin
                    if (!stb_sync2) begin
                        transaction_done <= 1'b0;
                        state <= S_IDLE;
                    end
                end
            endcase
        end
    end

    // Sync transaction_done to bus.clk
    reg done_sync1, done_sync2;
    always_ff @(posedge bus.clk) begin
        if (!rst_n) begin
            done_sync1 <= 1'b0;
            done_sync2 <= 1'b0;
            bus.ack <= 1'b0;
        end else begin
            done_sync1 <= transaction_done;
            done_sync2 <= done_sync1;

            // Generate single cycle ACK or hold until STB drops
            if (bus.stb && done_sync2) begin
                bus.ack  <= 1'b1;
                bus.stom <= latched_rdata;
            end else begin
                bus.ack <= 1'b0;
            end
        end
    end

    assign bus.err = 1'b0;
    assign bus.rty = !init_calib_complete;  // Retry until DDR initialized TODO: switch to error - dont stall the CPU, it should poll the businfo DDR3 status instead
    assign ddr_status = {(state != S_IDLE), init_calib_complete};

endmodule
