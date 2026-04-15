module cpu_top_fwd_tb;

    // ------------------------------------------------------------
    // Parameters
    // ------------------------------------------------------------
    localparam CLK_FREQ      = 27_000_000;
    localparam BAUD_RATE     = 115_200;
    localparam CLKS_PER_BIT  = CLK_FREQ / BAUD_RATE;
    localparam CLK_PERIOD_NS = 1_000_000_000ns / CLK_FREQ;
    localparam BIN_FILE      = "sample_fw.bin";

    // ------------------------------------------------------------
    // DUT signals
    // ------------------------------------------------------------
    logic clk    = 0;
    logic pin_rx = 1;  // idle high
    logic pin_tx;
    logic led4, led5;

    // ------------------------------------------------------------
    // Instantiate DUT
    // ------------------------------------------------------------
    cpu_top dut (
        .clk27   (clk),
        .pin_rx  (pin_rx),
        .pin_tx  (pin_tx),
        .btn_step(1'b1),  // not used in simulation
        .led4    (led4),
        .led5    (led5)
    );

    wire loading = dut.bl.loading;

    // ------------------------------------------------------------
    // Clock generation
    // ------------------------------------------------------------
    always #(CLK_PERIOD_NS / 2) clk = ~clk;

    // ------------------------------------------------------------
    // UART TX task
    // ------------------------------------------------------------
    task send_uart_byte(input [7:0] data);
        integer i;
        begin
            pin_rx = 0;
            repeat (CLKS_PER_BIT) @(posedge clk);
            for (i = 0; i < 8; i++) begin
                pin_rx = data[i];
                repeat (CLKS_PER_BIT) @(posedge clk);
            end
            pin_rx = 1;
            repeat (CLKS_PER_BIT) @(posedge clk);
        end
    endtask

    // Send a binary file via bootloader 'W' command
    task send_binary_file(input string filename);
        integer fd, r;
        logic [7:0] byte_val;
        integer fsize;
        begin
            // First pass: get file size
            fd = $fopen(filename, "rb");
            if (fd == 0) begin
                $display("FATAL: Could not open %s", filename);
                $finish;
            end
            fsize = 0;
            while (!$feof(fd)) begin
                r = $fread(byte_val, fd);
                if (r == 1) fsize++;
            end
            $fclose(fd);

            // Send 'W' + 2-byte length
            send_uart_byte(8'h57);          // 'W'
            send_uart_byte(fsize[15:8]);
            send_uart_byte(fsize[7:0]);

            // Second pass: send data
            fd = $fopen(filename, "rb");
            while (!$feof(fd)) begin
                r = $fread(byte_val, fd);
                if (r == 1) send_uart_byte(byte_val);
            end
            $fclose(fd);
            $display("[TB] Loaded %0d bytes from %s", fsize, filename);
        end
    endtask

    // Advance pipeline one clock via bootloader 'S' command
    task step_one;
        begin
            send_uart_byte(8'h53);  // 'S'
            repeat (4) @(posedge clk);
        end
    endtask

    // ------------------------------------------------------------
    // Register read helper (hierarchical access to regfile)
    // Path: dut (cpu_top) -> pipe (pipeline) -> ids (stageID) -> regs (regfile)
    // ------------------------------------------------------------
    function automatic logic [31:0] read_reg(input int unsigned idx);
        if (idx == 0) return 32'd0;
        return dut.pipe.sID.regs.data[idx];
    endfunction

    // ------------------------------------------------------------
    // Error tracking
    // ------------------------------------------------------------
    int errors = 0;

    task check_reg(input string name, input int unsigned idx, input logic [31:0] expected);
        logic [31:0] got;
        begin
            got = read_reg(idx);
            if (got !== expected) begin
                $display("FAIL [%s] x%0d: got=0x%08h  exp=0x%08h", name, idx, got, expected);
                errors++;
            end else begin
                $display("  OK [%s] x%0d = 0x%08h", name, idx, got);
            end
        end
    endtask

    // ------------------------------------------------------------
    // Test sequence
    // ------------------------------------------------------------
    initial begin
        $display("=== cpu_top_fwd testbench ===");

        // Wait for reset to deassert
        #(20 * CLK_PERIOD_NS);

        // --------------------------------------------------------
        // Phase 1: Load program via UART
        // --------------------------------------------------------
        $display("\n--- Phase 1: Loading program ---");
        send_binary_file(BIN_FILE);

        $display("[TB] Waiting for bootloader to finish...");
        wait (!loading);
        $display("[TB] Loading complete.");

        repeat (4) @(posedge clk);

        // --------------------------------------------------------
        // Phase 2: Release CPU and let it run
        // Send 'R' to bootloader, then wait enough cycles for
        // all 5 instructions to flow through the 6-stage pipeline.
        // --------------------------------------------------------
        $display("\n--- Phase 2: Running program (free-run) ---");
        send_uart_byte(8'h52);  // 'R' = release
        repeat (100) @(posedge clk);  // wait for pipeline to drain

        // --------------------------------------------------------
        // Phase 3: Examine registers
        // Expected (from sample_fw.s):
        //   addi x8, x0, 1      -> x8 = 1
        //   addi x9, x8, 1      -> x9 = 2
        //   add  x10, x9, x8    -> x10 = 3
        //   add  x11, x9, x8    -> x11 = 3
        //   addi x0, x0, 0  (nop)
        // --------------------------------------------------------
        $display("\n--- Phase 3: Register check ---");
        check_reg("addi x8,x0,1",   8,  32'd1);
        check_reg("addi x9,x8,1",   9,  32'd2);
        check_reg("add x10,x9,x8", 10,  32'd3);
        check_reg("add x11,x9,x8", 11,  32'd3);

        $display("\n--- Summary: %0d error(s) ---", errors);
        if (errors == 0)
            $display("PASS");
        else
            $display("FAIL");

        $finish;
    end

endmodule
