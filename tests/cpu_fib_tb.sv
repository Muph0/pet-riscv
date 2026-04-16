module cpu_fib_tb;

    // ------------------------------------------------------------
    // Parameters
    // ------------------------------------------------------------
    localparam CLK_FREQ = 27_000_000;
    localparam BAUD_RATE = 115_200;
    localparam CLKS_PER_BIT = CLK_FREQ / BAUD_RATE;
    localparam CLK_PERIOD_NS = 1_000_000_000ns / CLK_FREQ;
    localparam BIN_FILE = "sample_fib.bin";

    // ------------------------------------------------------------
    // DUT signals
    // ------------------------------------------------------------
    logic clk = 0;
    logic pin_rx = 1;  // idle high
    logic pin_tx;
    logic led4, led5;

    // ------------------------------------------------------------
    // Instantiate DUT
    // ------------------------------------------------------------
    cpu_top dut (
        .clk27 (clk),
        .pin_rx(pin_rx),
        .pin_tx(pin_tx),
        .led4  (led4),
        .led5  (led5)
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
            fd = $fopen(filename, "rb");
            if (fd == 0) begin
                $display("FATAL: Could not open %s", filename);
                $finish;
            end
            fsize = 0;
            while (!$feof(
                fd
            )) begin
                r = $fread(byte_val, fd);
                if (r == 1) fsize++;
            end
            $fclose(fd);

            send_uart_byte(8'h57);
            send_uart_byte(fsize[15:8]);
            send_uart_byte(fsize[7:0]);

            fd = $fopen(filename, "rb");
            while (!$feof(
                fd
            )) begin
                r = $fread(byte_val, fd);
                if (r == 1) send_uart_byte(byte_val);
            end
            $fclose(fd);
            $display("[TB] Loaded %0d bytes from %s", fsize, filename);
        end
    endtask

    // ------------------------------------------------------------
    // Data memory read helper (word-addressed)
    // ------------------------------------------------------------
    function automatic logic [31:0] read_dmem(input int unsigned word_idx);
        return dut.pipe.sMEM.data_mem.memory[word_idx];
    endfunction

    // ------------------------------------------------------------
    // Expected Fibonacci values
    // ------------------------------------------------------------
    logic [31:0] expected_fib[0:39];
    initial begin
        expected_fib[0] = 32'd0;
        expected_fib[1] = 32'd1;
        for (int i = 2; i < 40; i++) expected_fib[i] = expected_fib[i-1] + expected_fib[i-2];
    end

    // ------------------------------------------------------------
    // Error tracking
    // ------------------------------------------------------------
    int errors = 0;

    task check_dmem(input int unsigned word_idx, input logic [31:0] expected);
        logic [31:0] got;
        begin
            got = read_dmem(word_idx);
            if (got !== expected) begin
                $display("FAIL fib[%0d]: got=%0d  exp=%0d", word_idx, got, expected);
                errors++;
            end else begin
                $display("  OK fib[%0d] = %0d", word_idx, got);
            end
        end
    endtask

    // ------------------------------------------------------------
    // Test sequence
    // ------------------------------------------------------------
    initial begin
        $display("=== cpu_fib testbench (branch + Fibonacci) ===");

        #(20 * CLK_PERIOD_NS);

        // Phase 1: Load program
        $display("\n--- Phase 1: Loading program ---");
        send_binary_file(BIN_FILE);

        $display("[TB] Waiting for bootloader to finish...");
        wait (!loading);
        $display("[TB] Loading complete.");

        repeat (4) @(posedge clk);

        // Phase 2: Release CPU
        $display("\n--- Phase 2: Running program (free-run) ---");
        send_uart_byte(8'h52);  // 'R' = release
        repeat (500) @(posedge clk);

        // Phase 3: Check data memory for Fibonacci values
        $display("\n--- Phase 3: Data memory check (40 Fibonacci numbers) ---");
        for (int i = 0; i < 40; i++) begin
            check_dmem(i, expected_fib[i]);
        end

        $display("\n--- Summary: %0d error(s) ---", errors);
        if (errors == 0) $display("PASS");
        else $display("FAIL");

        $finish;
    end

endmodule
