module cpu_top_lw_tb;

    // ------------------------------------------------------------
    // Parameters
    // ------------------------------------------------------------
    localparam CLK_FREQ = 27_000_000;
    localparam BAUD_RATE = 115_200;
    localparam CLKS_PER_BIT = CLK_FREQ / BAUD_RATE;
    localparam CLK_PERIOD_NS = 1_000_000_000ns / CLK_FREQ;
    localparam BIN_FILE = "sample_lw.bin";

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
        .clk27   (clk),
        .pin_rx  (pin_rx),
        .pin_tx  (pin_tx),
        .btn_step(1'b1),
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
        $display("=== cpu_top_lw testbench (load-use hazard) ===");

        #(20 * CLK_PERIOD_NS);

        // Phase 1: Load program
        $display("\n--- Phase 1: Loading program ---");
        send_binary_file(BIN_FILE);

        $display("[TB] Waiting for bootloader to finish...");
        wait (!loading);
        $display("[TB] Loading complete.");

        repeat (4) @(posedge clk);

        // Phase 2: Release CPU
        // Program:
        //   addi x8, x0, 42     -> x8 = 42
        //   sw   x8, 0(x0)      -> mem[0] = 42
        //   lw   x9, 0(x0)      -> x9 = mem[0] = 42  (load)
        //   addi x10, x9, 1     -> x10 = 43           (use after load)
        //   nop
        $display("\n--- Phase 2: Running program (free-run) ---");
        send_uart_byte(8'h52);  // 'R' = release
        repeat (100) @(posedge clk);

        // Phase 3: Check registers
        $display("\n--- Phase 3: Register check ---");
        check_reg("addi x8,x0,42", 8, 32'd42);
        check_reg("lw x9,0(x0)", 9, 32'd42);
        check_reg("addi x10,x9,1", 10, 32'd43);

        $display("\n--- Summary: %0d error(s) ---", errors);
        if (errors == 0) $display("PASS");
        else $display("FAIL");

        $finish;
    end

endmodule
