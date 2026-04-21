`timescale 1ns/1ps

module DDR3_Memory_Interface_Top (
    input         clk,
    input         memory_clk,
    input         pll_lock,
    input         rst_n,
    input  [5:0]  app_burst_number,
    output        cmd_ready,
    input  [2:0]  cmd,
    input         cmd_en,
    input  [27:0] addr,
    output        wr_data_rdy,
    input  [127:0]wr_data,
    input         wr_data_en,
    input         wr_data_end,
    input  [15:0] wr_data_mask,
    output [127:0]rd_data,
    output        rd_data_valid,
    output        rd_data_end,
    input         sr_req,
    input         ref_req,
    output        sr_ack,
    output        ref_ack,
    output        init_calib_complete,
    output        clk_out,
    input         burst,
    output [13:0] O_ddr_addr,
    output [2:0]  O_ddr_ba,
    output        O_ddr_cs_n,
    output        O_ddr_ras_n,
    output        O_ddr_cas_n,
    output        O_ddr_we_n,
    output        O_ddr_clk,
    output        O_ddr_clk_n,
    output        O_ddr_cke,
    output        O_ddr_odt,
    output        O_ddr_reset_n,
    output [1:0]  O_ddr_dqm,
    inout  [15:0] IO_ddr_dq,
    inout  [1:0]  IO_ddr_dqs,
    inout  [1:0]  IO_ddr_dqs_n,
    output        ddr_rst
);

    // Mock clock generation for clk_out (User app domain)
    reg mock_clk_out = 0;
    always #10 mock_clk_out = ~mock_clk_out; // 50 MHz for sim
    assign clk_out = mock_clk_out;

    // Initialization mock
    reg init_done = 0;
    initial begin
        init_done = 0;
        #1000 init_done = 1;
    end
    assign init_calib_complete = init_done;

    // Command/Data ready are always active in this simple model if init is done
    assign cmd_ready = init_done;
    assign wr_data_rdy = init_done;

    // Simple sparse memory holding 128-bit words using an associative array
    reg [127:0] mem_array [*];

    reg [127:0] rdata_out;
    reg         rdata_valid_out;
    integer     read_delay;

    // Process commands
    always @(posedge mock_clk_out) begin
        if (!rst_n) begin
            rdata_valid_out <= 0;
            read_delay <= 0;
        end else begin
            rdata_valid_out <= 0;

            if (read_delay > 0) begin
                read_delay <= read_delay - 1;
                if (read_delay == 1) begin
                    rdata_valid_out <= 1;
                end
            end else if (cmd_en && init_done) begin
                // Write Command (0)
                if (cmd == 3'd0) begin
                    // Write data is expected to be present with wr_data_en
                    // But in tester / interface, it's pushed asynchronously/independently.
                    // This sim assumes it's arriving exactly when the command is logged!
                    // In reality, it pushes to FIFO.
                end
                // Read Command (1)
                else if (cmd == 3'd1) begin
                    read_delay <= 3; // fake delay
                    if (mem_array.exists(addr)) begin
                        rdata_out <= mem_array[addr];
                    end else begin
                        rdata_out <= 128'hdeadbeef_deadbeef_deadbeef_deadbeef;
                    end
                end
            end

            // Just store whatever is on wr_data bus when wr_data_en is high
            // For a robust simulation we'd track FIFO pushes, but this simulates
            // a single synchronized write perfectly well for now.
            if (wr_data_en && init_done) begin
                reg [127:0] current_val;
                reg [127:0] new_val;
                if (mem_array.exists(addr)) current_val = mem_array[addr];
                else current_val = 128'h0;

                new_val = current_val;
                // Apply active-high write mask (1=no write, 0=write)
                if (wr_data_mask[ 0] == 1'b0) new_val[  7:  0] = wr_data[  7:  0];
                if (wr_data_mask[ 1] == 1'b0) new_val[ 15:  8] = wr_data[ 15:  8];
                if (wr_data_mask[ 2] == 1'b0) new_val[ 23: 16] = wr_data[ 23: 16];
                if (wr_data_mask[ 3] == 1'b0) new_val[ 31: 24] = wr_data[ 31: 24];
                if (wr_data_mask[ 4] == 1'b0) new_val[ 39: 32] = wr_data[ 39: 32];
                if (wr_data_mask[ 5] == 1'b0) new_val[ 47: 40] = wr_data[ 47: 40];
                if (wr_data_mask[ 6] == 1'b0) new_val[ 55: 48] = wr_data[ 55: 48];
                if (wr_data_mask[ 7] == 1'b0) new_val[ 63: 56] = wr_data[ 63: 56];
                if (wr_data_mask[ 8] == 1'b0) new_val[ 71: 64] = wr_data[ 71: 64];
                if (wr_data_mask[ 9] == 1'b0) new_val[ 79: 72] = wr_data[ 79: 72];
                if (wr_data_mask[10] == 1'b0) new_val[ 87: 80] = wr_data[ 87: 80];
                if (wr_data_mask[11] == 1'b0) new_val[ 95: 88] = wr_data[ 95: 88];
                if (wr_data_mask[12] == 1'b0) new_val[103: 96] = wr_data[103: 96];
                if (wr_data_mask[13] == 1'b0) new_val[111:104] = wr_data[111:104];
                if (wr_data_mask[14] == 1'b0) new_val[119:112] = wr_data[119:112];
                if (wr_data_mask[15] == 1'b0) new_val[127:120] = wr_data[127:120];

                // Write it directly using current bus.addr which is stable during stb
                mem_array[addr] = new_val;
            end
        end
    end

    assign rd_data = rdata_out;
    assign rd_data_valid = rdata_valid_out;
    assign rd_data_end = rdata_valid_out; // End pulse on single bursts

    // Stubs
    assign sr_ack = 0;
    assign ref_ack = 0;
    assign ddr_rst = 0;
    assign O_ddr_addr = 0;
    assign O_ddr_ba = 0;
    assign O_ddr_cs_n = 1;
    assign O_ddr_ras_n = 1;
    assign O_ddr_cas_n = 1;
    assign O_ddr_we_n = 1;
    assign O_ddr_clk = 0;
    assign O_ddr_clk_n = 1;
    assign O_ddr_cke = 0;
    assign O_ddr_odt = 0;
    assign O_ddr_reset_n = 1;
    assign O_ddr_dqm = 0;

endmodule