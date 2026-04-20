module cpu_boot_decode_tb;
    import mem_pkg::*;

    // ------------------------------------------------------------
    // Parameters
    // ------------------------------------------------------------
    localparam CLK_FREQ = 27_000_000;
    localparam BAUD_RATE = 115_200;
    localparam CLKS_PER_BIT = CLK_FREQ / BAUD_RATE;
    localparam CLK_PERIOD_NS = 1_000_000_000ns / CLK_FREQ;
    localparam BIN_FILE = "sample1.bin";

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
        .key2  (1'b1),
        .pin_rx(pin_rx),
        .pin_tx(pin_tx),
        .led4  (led4),
        .led5  (led5)
    );

    wire loading = dut.u_uart.bl.loading;

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

    // Send an entire binary file via bootloader 'W' command
    task send_binary_file(input string filename);
        integer fd, r;
        logic [7:0] byte_val;
        integer count;
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
            send_uart_byte(fsize[15:8]);
            send_uart_byte(fsize[7:0]);

            fd = $fopen(filename, "rb");
            count = 0;
            while (!$feof(
                fd
            )) begin
                r = $fread(byte_val, fd);
                if (r == 1) begin
                    send_uart_byte(byte_val);
                    count++;
                end
            end
            $fclose(fd);
            $display("[TB] Sent W command: %0d bytes from %s", count, filename);
        end
    endtask

    // ------------------------------------------------------------
    // Register read helper
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
        $display("=== CPU Boot & Decode Testbench ===");

        #(20 * CLK_PERIOD_NS);

        // Phase 1: Load program via UART
        $display("\n--- Phase 1: Loading program via UART ---");
        send_binary_file(BIN_FILE);

        $display("[TB] Waiting for bootloader to finish...");
        wait (!loading);
        $display("[TB] Loading complete, CPU ready.");
        repeat (4) @(posedge clk);

        // Phase 2: Run the program
        $display("\n--- Phase 2: Running program (free-run) ---");
        send_uart_byte(8'h44);  // 'D' = done/release
        repeat (500) @(posedge clk);

        // Phase 3: Check register results
        $display("\n--- Phase 3: Register check ---");
        check_reg("lui+addi x1", 1, 32'h12344FFF);
        check_reg("auipc x2", 2, 32'h00005004);
        check_reg("slti x3", 3, 32'h0);
        check_reg("sltiu x4", 4, 32'h0);
        check_reg("xori x5", 5, 32'h12344C00);
        check_reg("ori x6", 6, 32'h12344FFF);
        check_reg("andi x7", 7, 32'h0000000F);
        check_reg("slli x8", 8, 32'h2344FFF0);
        check_reg("srli x9", 9, 32'h012344FF);
        check_reg("srai x10", 10, 32'h012344FF);
        check_reg("add x11", 11, 32'h1234A003);
        check_reg("sub x12", 12, 32'h1233FFFB);
        check_reg("sll x13", 13, 32'h4FFF0000);
        check_reg("slt x14", 14, 32'h0);
        check_reg("sltu x15", 15, 32'h0);
        check_reg("xor x16", 16, 32'h12341FFB);
        check_reg("srl x17", 17, 32'h00001234);
        check_reg("sra x18", 18, 32'h00001234);
        check_reg("or x19", 19, 32'h12345FFF);
        check_reg("and x20", 20, 32'h00004004);

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
        #50ms;
        $display("FATAL: Watchdog timeout - simulation hung.");
        $dumpflush;
        $finish;
    end

endmodule
