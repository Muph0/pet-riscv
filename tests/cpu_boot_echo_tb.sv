module cpu_boot_echo_tb;

    // ------------------------------------------------------------
    // Parameters
    // ------------------------------------------------------------
    localparam CLK_FREQ = 27_000_000;
    localparam BAUD_RATE = 115_200;
    localparam CLKS_PER_BIT = CLK_FREQ / BAUD_RATE;
    localparam CLK_PERIOD_NS = 1_000_000_000ns / CLK_FREQ;
    localparam BIN_FILE = "boot_echo.bin";

    // ------------------------------------------------------------
    // DUT signals
    // ------------------------------------------------------------
    logic clk = 0;
    logic pin_rx = 1;
    logic pin_tx;
    logic led4, led5;

    // ------------------------------------------------------------
    // Expected data
    // ------------------------------------------------------------
    localparam int BANNER_LEN = 36;
    logic [7:0] banner_bytes[BANNER_LEN] = '{
        8'h48,
        8'h65,
        8'h6C,
        8'h6C,
        8'h6F,
        8'h20,
        8'h66,
        8'h72,
        8'h6F,
        8'h6D,
        8'h20,
        8'h52,
        8'h49,
        8'h53,
        8'h43,
        8'h2D,
        8'h56,
        8'h21,
        8'h20,
        8'h54,
        8'h79,
        8'h70,
        8'h65,
        8'h20,
        8'h73,
        8'h6F,
        8'h6D,
        8'h65,
        8'h74,
        8'h68,
        8'h69,
        8'h6E,
        8'h67,
        8'h3A,
        8'h0D,
        8'h0A
    };

    localparam int N_ECHO = 4;
    logic [7:0] test_bytes  [N_ECHO] = '{8'h61, 8'h42, 8'h7A, 8'h59};
    logic [7:0] expect_bytes[N_ECHO] = '{8'h41, 8'h62, 8'h5A, 8'h79};

    // ------------------------------------------------------------
    wishbone ext_ddr_bus (
        .clk  (clk),
        .reset(1'b0)
    );
    logic [1:0] ext_ddr_status = 2'b01;

    // Instantiate DUT
    // ------------------------------------------------------------
    cpu_top dut (
        .clk27(clk),
        .key2(1'b1),
        .pin_rx(pin_rx),
        .pin_tx(pin_tx),
        .led4(led4),
        .led5(led5),
        .ext_ddr_bus(ext_ddr_bus),
        .ext_ddr_status(ext_ddr_status)
    );

    wire loading = dut.u_uart.bl.loading;

    // ------------------------------------------------------------
    // Clock generation
    // ------------------------------------------------------------
    always #(CLK_PERIOD_NS / 2) clk = ~clk;

    // ------------------------------------------------------------
    // UART TX task (testbench -> DUT)
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

    // ------------------------------------------------------------
    // UART RX task (DUT -> testbench)
    // ------------------------------------------------------------
    task recv_uart_byte(output [7:0] data);
        integer i;
        begin
            @(negedge pin_tx);
            repeat (CLKS_PER_BIT / 2) @(posedge clk);
            repeat (CLKS_PER_BIT) @(posedge clk);
            for (i = 0; i < 8; i++) begin
                data[i] = pin_tx;
                if (i < 7) repeat (CLKS_PER_BIT) @(posedge clk);
            end
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
    // RX collection and checks
    // ------------------------------------------------------------
    logic [7:0] rx_fifo[$];
    int errors = 0;

    initial begin
        logic [7:0] b;
        forever begin
            recv_uart_byte(b);
            rx_fifo.push_back(b);
            $display("[TB-RX] Got 0x%02h ('%c') (fifo size=%0d)", b, b, rx_fifo.size());
        end
    end

    task wait_for_rx_count(input int expected_count, input int timeout_bits, input string phase);
        int waited_bits;
        begin
            waited_bits = 0;
            while (rx_fifo.size() < expected_count && waited_bits < timeout_bits) begin
                repeat (CLKS_PER_BIT) @(posedge clk);
                waited_bits++;
            end
            if (rx_fifo.size() < expected_count) begin
                $display("FAIL [%s]: timeout waiting for %0d bytes, got %0d", phase,
                         expected_count, rx_fifo.size());
                errors++;
            end
        end
    endtask

    task check_and_pop_byte(input string phase, input int idx, input logic [7:0] expected);
        logic [7:0] got;
        begin
            if (rx_fifo.size() == 0) begin
                $display("FAIL [%s %0d]: no byte available", phase, idx);
                errors++;
            end else begin
                got = rx_fifo.pop_front();
                if (got !== expected) begin
                    $display("FAIL [%s %0d]: got=0x%02h exp=0x%02h", phase, idx, got, expected);
                    errors++;
                end else begin
                    $display("  OK [%s %0d] = 0x%02h ('%c')", phase, idx, got, got);
                end
            end
        end
    endtask

    // ------------------------------------------------------------
    // Main test sequence
    // ------------------------------------------------------------
    initial begin
        $display("=== CPU Boot Echo Testbench ===");

        #(20 * CLK_PERIOD_NS);

        $display("\n--- Phase 1: Loading program via bootloader ---");
        send_binary_file(BIN_FILE);

        $display("[TB] Waiting for bootloader to finish...");
        wait (!loading);
        $display("[TB] Loading complete.");
        repeat (4) @(posedge clk);

        $display("\n--- Phase 2: Release CPU and capture banner ---");
        send_uart_byte(8'h44);
        wait_for_rx_count(BANNER_LEN, BANNER_LEN * 16, "banner");

        for (int i = 0; i < BANNER_LEN; i++) begin
            check_and_pop_byte("banner", i, banner_bytes[i]);
        end

        if (rx_fifo.size() != 0) begin
            $display("FAIL [banner]: expected fifo empty after banner, got %0d leftover byte(s)",
                     rx_fifo.size());
            errors++;
            while (rx_fifo.size() > 0) void'(rx_fifo.pop_front());
        end

        $display("\n--- Phase 3: Send characters and check echoed case-flip ---");
        for (int i = 0; i < N_ECHO; i++) begin
            $display("[TB] Sending 0x%02h ('%c')", test_bytes[i], test_bytes[i]);
            send_uart_byte(test_bytes[i]);
            wait_for_rx_count(1, 20, $sformatf("echo %0d", i));
            check_and_pop_byte("echo", i, expect_bytes[i]);
        end

        $display("\n=== Test complete: %0d errors ===", errors);
        if (errors == 0) $display("ALL PASSED");
        else $display("SOME TESTS FAILED");

        #(10 * CLK_PERIOD_NS);
        $dumpflush;
        $finish;
    end

    initial begin
        #250ms;
        $display("FATAL: Watchdog timeout - simulation hung.");
        $dumpflush;
        $finish;
    end

endmodule
