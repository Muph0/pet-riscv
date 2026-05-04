// =============================================================================
// cpu_memtest_tb — Run the Rust memtest binary against a 128 MB mock DDR3.
//
// Strategy
// --------
// * ROM is preloaded with memtest.bin by force-driving the bootloader's
//   byte-write port (dut.bl_mem_{addr,data,write}) at 1 clock per byte,
//   bypassing the slow UART path entirely.
// * A simple always_ff wishbone slave responds to ext_ddr_bus with a flat
//   128 MB memory array (1-cycle registered ACK, byte-select aware).
// * After loading, a single 'D' byte is sent via UART to release the CPU.
// * UART output is printed to the console; the test finishes as soon as
//   "DONE" or "fail" appears in the stream, or a timeout fires.
// =============================================================================

module cpu_memtest_tb;

    // -------------------------------------------------------------------------
    // Parameters
    // -------------------------------------------------------------------------
    localparam CLK_FREQ = 27_000_000;
    localparam BAUD_RATE = 115_200;
    localparam CLKS_PER_BIT = CLK_FREQ / BAUD_RATE;
    localparam CLK_PERIOD_NS = 1_000_000_000ns / CLK_FREQ;
    localparam BIN_FILE = "memtest.bin";

    // Mock array covers full 128 MB so no bounds issues regardless of reported range.
    // DDR3_END_ADDR (below) controls what the firmware actually tests.
    localparam DDR_WORDS = 32 * 1024 * 1024;  // 128 MB = 33 554 432 words

    // Tell the firmware DDR3 ends at 16kB so the test completes quickly in sim.
    // defparam overrides businfo_wb.DDR3_END_ADDR without touching the RTL default.
    defparam dut.u_businfo.DDR3_END_ADDR = 32'h8000_3FFF;

    // -------------------------------------------------------------------------
    // Clock & UART pins
    // -------------------------------------------------------------------------
    logic clk = 0;
    logic pin_rx = 1;
    logic pin_tx;
    logic led4, led5;

    always #(CLK_PERIOD_NS / 2) clk = ~clk;

    // -------------------------------------------------------------------------
    // Mock DDR3: 128 MB flat memory, single-cycle registered Wishbone slave.
    //
    // Address mapping:
    //   bus.adr = 0x8000_0000 → adr[26:2] = 25'h0   (word 0)
    //   bus.adr = 0x87FF_FFFC → adr[26:2] = 25'h1FF_FFFF (word 33554431)
    //   (bit 31 is set for the DDR region but falls outside [26:2])
    // -------------------------------------------------------------------------
    wishbone ext_ddr_bus (
        .clk  (clk),
        .reset(1'b0)
    );
    logic [1:0] ext_ddr_status = 2'b01;  // init_calib_complete = 1

    logic [31:0] ddr_mem[0:DDR_WORDS-1];

    always_ff @(posedge clk) begin
        ext_ddr_bus.ack <= 1'b0;
        ext_ddr_bus.err <= 1'b0;
        ext_ddr_bus.rty <= 1'b0;
        if (ext_ddr_bus.stb && ext_ddr_bus.cyc) begin
            if (ext_ddr_bus.we) begin
                if (ext_ddr_bus.sel[0])
                    ddr_mem[ext_ddr_bus.adr[26:2]][7:0] <= ext_ddr_bus.mtos[7:0];
                if (ext_ddr_bus.sel[1])
                    ddr_mem[ext_ddr_bus.adr[26:2]][15:8] <= ext_ddr_bus.mtos[15:8];
                if (ext_ddr_bus.sel[2])
                    ddr_mem[ext_ddr_bus.adr[26:2]][23:16] <= ext_ddr_bus.mtos[23:16];
                if (ext_ddr_bus.sel[3])
                    ddr_mem[ext_ddr_bus.adr[26:2]][31:24] <= ext_ddr_bus.mtos[31:24];
            end else begin
                ext_ddr_bus.stom <= ddr_mem[ext_ddr_bus.adr[26:2]];
            end
            ext_ddr_bus.ack <= 1'b1;
        end
    end

    // -------------------------------------------------------------------------
    // DUT
    // -------------------------------------------------------------------------
    cpu_top dut (
        .clk27         (clk),
        .key2          (1'b1),
        .pin_rx        (pin_rx),
        .pin_tx        (pin_tx),
        .led4          (led4),
        .led5          (led5),
        .ext_ddr_bus   (ext_ddr_bus),
        .ext_ddr_status(ext_ddr_status)
    );

    wire loading = dut.u_uart.bl.loading;

    // -------------------------------------------------------------------------
    // UART TX task  (TB → DUT, LSB first)
    // -------------------------------------------------------------------------
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

    // -------------------------------------------------------------------------
    // UART RX task  (DUT → TB)
    // -------------------------------------------------------------------------
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

    // -------------------------------------------------------------------------
    // ROM preload
    //
    // Force-drives dut.bl_mem_{addr,data,write} at one byte per clock cycle,
    // exactly matching what the UART bootloader would do but ~234× faster.
    // The wb_dp_4Kx32b accumulates bytes into 32-bit words and commits on
    // every 4th byte (bl_addr[1:0] == 2'b11).
    // -------------------------------------------------------------------------
    task load_rom(input string filename);
        integer fd, r, addr;
        logic [7:0] byte_val;
        begin
            fd = $fopen(filename, "rb");
            if (fd == 0) begin
                $display("FATAL: Cannot open binary '%s'", filename);
                $finish;
            end

            addr = 0;
            force dut.bl_mem_write = 1'b0;
            force dut.bl_mem_addr = 32'b0;
            force dut.bl_mem_data = 8'b0;
            @(posedge clk);

            while (!$feof(
                fd
            )) begin
                r = $fread(byte_val, fd);
                if (r == 1) begin
                    force dut.bl_mem_addr = addr;
                    force dut.bl_mem_data = byte_val;
                    force dut.bl_mem_write = 1'b1;
                    @(posedge clk);
                    addr = addr + 1;
                end
            end
            $fclose(fd);

            force dut.bl_mem_write = 1'b0;
            @(posedge clk);
            release dut.bl_mem_write;
            release dut.bl_mem_addr;
            release dut.bl_mem_data;

            $display("[TB] Loaded %0d bytes from %s", addr, filename);
        end
    endtask

    // -------------------------------------------------------------------------
    // UART output monitor
    //
    // Runs as a permanent background process.  Prints each character to the
    // console and detects "DONE" and "fail" (4-byte sliding window).
    // Fires ev_done when a result keyword is seen.
    // -------------------------------------------------------------------------
    event ev_done;
    integer test_result = 0;  // 0 = in progress, 1 = pass, -1 = fail

    logic [7:0] rx_hist[4] = '{default: 8'h00};

    initial begin : uart_monitor
        logic [7:0] b;
        forever begin
            recv_uart_byte(b);
            $write("%c", b);

            rx_hist[0] = rx_hist[1];
            rx_hist[1] = rx_hist[2];
            rx_hist[2] = rx_hist[3];
            rx_hist[3] = b;

            // "DONE" — rust_main prints "Memtest: DONE"
            if (rx_hist[0] == "D" && rx_hist[1] == "O" &&
                rx_hist[2] == "N" && rx_hist[3] == "E") begin
                test_result = 1;
                ->ev_done;
            end

            // "fail" — check_pass returns Err("check failed")
            if (rx_hist[0] == "f" && rx_hist[1] == "a" &&
                rx_hist[2] == "i" && rx_hist[3] == "l") begin
                test_result = -1;
                ->ev_done;
            end
        end
    end

    // -------------------------------------------------------------------------
    // Main sequence
    // -------------------------------------------------------------------------
    int errors = 0;

    initial begin
        $display("=== CPU Memtest Testbench ===");
        $display("    DDR3 mock: %0d MB, 1-cycle ACK", DDR_WORDS / (256 * 1024));

        // Let POR release
        repeat (10) @(posedge clk);

        // ---- Phase 1: Preload ROM with the memtest binary ----
        $display("\n--- Phase 1: Loading ROM ---");
        load_rom(BIN_FILE);
        repeat (4) @(posedge clk);

        // ---- Phase 2: Release the CPU via bootloader 'D' command ----
        $display("--- Phase 2: Releasing CPU (sending 'D') ---");
        send_uart_byte(8'h44);  // 'D' = done/run

        // ---- Phase 3: Run and monitor UART output ----
        $display("--- Phase 3: Running memtest (monitoring UART output) ---\n");

        fork
            // Wait for ev_done (PASS or FAIL keyword detected)
            @(ev_done);

            // Hard timeout: 1 G cycles ≈ 37 s at 27 MHz
            // Covers ~4 full 128 MB passes with instruction overhead.
            begin : timeout_proc
                repeat (1_000_000_000) @(posedge clk);
                $display("\n\n[TB] TIMEOUT — no DONE/fail after 1G cycles");
                errors = errors + 1;
                ->ev_done;
            end
        join_any
        disable fork;

        $display("");

        case (test_result)
            1: $display("[TB] Memtest PASSED");
            -1: begin
                $display("[TB] Memtest FAILED (check failed)");
                errors = errors + 1;
            end
            default: ;  // timeout already counted
        endcase

        if (errors == 0) $display("\n=== ALL PASSED ===");
        else $display("\n=== FAILED: %0d error(s) ===", errors);

        $finish;
    end

endmodule
