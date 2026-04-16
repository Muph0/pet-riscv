`timescale 1ns / 1ps

module uart_rx_tb;

    // ------------------------------------------------------------
    // Parameters
    // ------------------------------------------------------------
    localparam CLK_FREQ = 27_000_000;
    localparam BAUD_RATE = 115_200;
    localparam CLKS_PER_BIT = CLK_FREQ / BAUD_RATE;
    localparam CLK_PERIOD_NS = 1_000_000_000 / CLK_FREQ;  // ns per clock

    // ------------------------------------------------------------
    // DUT signals
    // ------------------------------------------------------------
    logic       clk = 0;
    logic       reset = 1;
    logic       rx0 = 1;  // idle high
    logic [7:0] data_out;
    logic       data_valid;

    // ------------------------------------------------------------
    // Instantiate DUT
    // ------------------------------------------------------------
    uart_rx #(
        .CLKS_PER_BIT(CLKS_PER_BIT)
    ) dut (
        .clk(clk),
        .reset(reset),
        .rx0(rx0),
        .data_out(data_out),
        .data_valid(data_valid)
    );

    // ------------------------------------------------------------
    // Clock generation
    // ------------------------------------------------------------
    always #(CLK_PERIOD_NS / 2) clk = ~clk;

    // ------------------------------------------------------------
    // UART send tasks
    // ------------------------------------------------------------
    task send_uart_byte(input [7:0] bbyte);
        integer i;
        begin
            // Start bit
            rx0 = 0;
            #(CLKS_PER_BIT * CLK_PERIOD_NS);

            // Data bits (LSB first)
            for (i = 0; i < 8; i++) begin
                rx0 = bbyte[i];
                #(CLKS_PER_BIT * CLK_PERIOD_NS);
            end

            // Stop bit
            rx0 = 1;
            #(CLKS_PER_BIT * CLK_PERIOD_NS);
        end
    endtask

    task send_uart_byte_no_stop(input [7:0] bbyte);
        integer i;
        begin
            // Start bit
            rx0 = 0;
            #(CLKS_PER_BIT * CLK_PERIOD_NS);

            // Data bits (LSB first)
            for (i = 0; i < 8; i++) begin
                rx0 = bbyte[i];
                #(CLKS_PER_BIT * CLK_PERIOD_NS);
            end

            // No stop bit - drive line low instead
            rx0 = 0;
            #(CLKS_PER_BIT * CLK_PERIOD_NS);

            // Return to idle
            rx0 = 1;
        end
    endtask

    // ------------------------------------------------------------
    // Test sequence
    // ------------------------------------------------------------
    initial begin
        logic [7:0] test_value;
        $dumpfile("uart_rx_tb.vcd");
        $dumpvars(0, uart_rx_tb);
        $display("Starting UART RX testbench");

        // Hold reset
        #(10 * CLK_PERIOD_NS);
        reset = 0;

        // ----------------------------------------------------------
        // Case 1: single byte
        // ----------------------------------------------------------
        $display("\n--- Case 1: single byte ---");
        test_value = 8'hA5;
        $display("Sending byte: %02X", test_value);
        send_uart_byte(test_value);
        wait (data_valid == 1);
        $display("Received byte: %02X", data_out);
        if (data_out == test_value) $display("TEST PASSED");
        else $display("TEST FAILED: expected %02X, got %02X", test_value, data_out);

        #(1000 * CLK_PERIOD_NS);

        // ----------------------------------------------------------
        // Case 2: two bytes back to back
        // ----------------------------------------------------------
        $display("\n--- Case 2: two bytes back to back ---");
        test_value = 8'h3C;
        $display("Sending first byte: %02X", test_value);
        send_uart_byte(test_value);
        wait (data_valid == 1);
        $display("Received byte: %02X", data_out);
        if (data_out == test_value) $display("TEST PASSED");
        else $display("TEST FAILED: expected %02X, got %02X", test_value, data_out);

        test_value = 8'h7E;
        $display("Sending second byte: %02X", test_value);
        send_uart_byte(test_value);
        wait (data_valid == 1);
        $display("Received byte: %02X", data_out);
        if (data_out == test_value) $display("TEST PASSED");
        else $display("TEST FAILED: expected %02X, got %02X", test_value, data_out);

        #(1000 * CLK_PERIOD_NS);

        // ----------------------------------------------------------
        // Case 3: byte without stop bit (framing error - data_valid
        //         should NOT be asserted)
        // ----------------------------------------------------------
        $display("\n--- Case 3: byte without stop bit (framing error) ---");
        test_value = 8'hB4;
        $display("Sending byte without stop bit: %02X", test_value);
        send_uart_byte_no_stop(test_value);
        // Give the DUT enough time to finish processing the stop slot
        #(2 * CLKS_PER_BIT * CLK_PERIOD_NS);
        if (data_valid == 0) $display("TEST PASSED: data_valid not asserted on framing error");
        else $display("TEST FAILED: data_valid asserted despite missing stop bit");

        #(1000 * CLK_PERIOD_NS);
        $dumpflush;
        $finish;
    end

endmodule
