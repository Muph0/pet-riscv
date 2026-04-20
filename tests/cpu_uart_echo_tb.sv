module cpu_uart_echo_tb;

    // ------------------------------------------------------------
    // Parameters
    // ------------------------------------------------------------
    localparam CLK_FREQ = 27_000_000;
    localparam BAUD_RATE = 115_200;
    localparam CLKS_PER_BIT = CLK_FREQ / BAUD_RATE;
    localparam CLK_PERIOD_NS = 1_000_000_000ns / CLK_FREQ;
    localparam BIN_FILE = "sample_uart_echo.bin";

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
    // UART TX task (testbench → DUT)
    // ------------------------------------------------------------
    task send_uart_byte(input [7:0] data);
        integer i;
        begin
            pin_rx = 0;  // start bit
            repeat (CLKS_PER_BIT) @(posedge clk);
            for (i = 0; i < 8; i++) begin
                pin_rx = data[i];
                repeat (CLKS_PER_BIT) @(posedge clk);
            end
            pin_rx = 1;  // stop bit
            repeat (CLKS_PER_BIT) @(posedge clk);
        end
    endtask

    // ------------------------------------------------------------
    // UART RX task (DUT → testbench)
    // ------------------------------------------------------------
    task recv_uart_byte(output [7:0] data);
        integer i;
        begin
            // Wait for start bit (falling edge on pin_tx)
            @(negedge pin_tx);
            // Sample in the middle of each bit
            repeat (CLKS_PER_BIT / 2) @(posedge clk);  // middle of start bit
            repeat (CLKS_PER_BIT) @(posedge clk);  // middle of bit 0
            for (i = 0; i < 8; i++) begin
                data[i] = pin_tx;
                if (i < 7) repeat (CLKS_PER_BIT) @(posedge clk);
            end
            // Wait through stop bit
            repeat (CLKS_PER_BIT) @(posedge clk);
        end
    endtask

    // ------------------------------------------------------------
    // Send binary file via bootloader 'W' command
    // ------------------------------------------------------------
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

            send_uart_byte(8'h57);  // 'W'
            send_uart_byte(fsize[15:8]);  // size high
            send_uart_byte(fsize[7:0]);  // size low

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
    // Error tracking
    // ------------------------------------------------------------
    int errors = 0;

    // ------------------------------------------------------------
    // Test data — lowercase letters to send
    // ------------------------------------------------------------
    localparam int N_TEST = 5;
    logic [7:0] test_bytes     [N_TEST] = '{8'h68, 8'h65, 8'h6C, 8'h6C, 8'h6F};  // "hello"
    logic [7:0] expect_bytes   [N_TEST] = '{8'h48, 8'h45, 8'h4C, 8'h4C, 8'h4F};  // "HELLO"

    // ------------------------------------------------------------
    // Receiver FIFO — collects all bytes from DUT tx in order
    // ------------------------------------------------------------
    logic [7:0] rx_fifo        [     $];
    logic       rx_running = 0;

    initial begin
        logic [7:0] b;
        forever begin
            recv_uart_byte(b);
            rx_fifo.push_back(b);
            $display("[TB-RX] Got 0x%02h ('%c')  (fifo size=%0d)", b, b, rx_fifo.size());
        end
    end

    // ------------------------------------------------------------
    // Main test sequence
    // ------------------------------------------------------------
    initial begin
        $display("=== UART Echo Testbench ===");

        #(20 * CLK_PERIOD_NS);

        // Phase 1: Load program via bootloader
        $display("\n--- Phase 1: Loading program ---");
        send_binary_file(BIN_FILE);

        $display("[TB] Waiting for bootloader to finish...");
        wait (!loading);
        $display("[TB] Loading complete.");
        repeat (4) @(posedge clk);

        // Phase 2: Release CPU
        $display("\n--- Phase 2: Release CPU ---");
        send_uart_byte(8'h52);  // 'R'

        // Wait for the program to start and drain any stale RX data
        // The UART periph RX captured bootloader traffic; the echo program
        // will echo those stale bytes. Wait for them to flush out.
        $display("[TB] Flushing stale echo bytes...");
        repeat (CLKS_PER_BIT * 30) @(posedge clk);
        // Discard anything received so far
        while (rx_fifo.size() > 0) begin
            $display("[TB] Discarding stale byte: 0x%02h", rx_fifo[0]);
            void'(rx_fifo.pop_front());
        end

        // Phase 3: Send test bytes one at a time
        $display("\n--- Phase 3: Sending test bytes ---");
        for (int i = 0; i < N_TEST; i++) begin
            $display("[TB] Sending byte %0d: 0x%02h ('%c')", i, test_bytes[i], test_bytes[i]);
            send_uart_byte(test_bytes[i]);
            // Wait long enough for the echo to complete before sending next
            repeat (CLKS_PER_BIT * 12) @(posedge clk);
        end

        // Wait for all responses
        repeat (CLKS_PER_BIT * 15) @(posedge clk);

        // Phase 4: Check results
        $display("\n--- Phase 4: Checking results ---");
        if (rx_fifo.size() != N_TEST) begin
            $display("FAIL: expected %0d replies, got %0d", N_TEST, rx_fifo.size());
            errors++;
        end

        for (int i = 0; i < N_TEST && i < rx_fifo.size(); i++) begin
            if (rx_fifo[i] !== expect_bytes[i]) begin
                $display("FAIL byte[%0d]: got=0x%02h  exp=0x%02h", i, rx_fifo[i], expect_bytes[i]);
                errors++;
            end else begin
                $display("  OK byte[%0d] = 0x%02h ('%c')", i, rx_fifo[i], rx_fifo[i]);
            end
        end

        // Summary
        $display("\n=== Test complete: %0d errors ===", errors);
        if (errors == 0) $display("ALL PASSED");
        else $display("SOME TESTS FAILED");

        #(10 * CLK_PERIOD_NS);
        $dumpflush;
        $finish;
    end

    // Watchdog
    initial begin
        #200ms;
        $display("FATAL: Watchdog timeout - simulation hung.");
        $dumpflush;
        $finish;
    end

endmodule
