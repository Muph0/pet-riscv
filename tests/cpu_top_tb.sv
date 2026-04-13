module cpu_top_tb;

    // ------------------------------------------------------------
    // Parameters
    // ------------------------------------------------------------
    localparam CLK_FREQ      = 27_000_000;
    localparam BAUD_RATE     = 115_200;
    localparam CLKS_PER_BIT  = CLK_FREQ / BAUD_RATE;
    localparam CLK_PERIOD_NS = 1_000_000_000ns / CLK_FREQ;
    localparam BIN_FILE      = "sample1.bin";

    // ------------------------------------------------------------
    // DUT signals
    // ------------------------------------------------------------
    logic clk     = 0;
    logic pin_rx  = 1;  // idle high
    logic pin_tx;
    logic pin_step = 1; // active-low, idle = not pressed
    logic pin_p9, led4, led5;

    // ------------------------------------------------------------
    // Instantiate DUT
    // ------------------------------------------------------------
    cpu_top dut (
        .clk27   (clk),
        .pin_rx  (pin_rx),
        .pin_tx  (pin_tx),
        .pin_step(pin_step),
        .pin_p9  (pin_p9),
        .led4    (led4),
        .led5    (led5)
    );

    // Convenience aliases into the DUT hierarchy
    wire [6:0]  id_opcode = dut.id_io.opcode;
    wire [4:0]  id_rd     = dut.id_io.rd;
    wire [2:0]  id_funct3 = dut.id_io.funct3;
    wire [4:0]  id_rs1    = dut.id_io.rs1;
    wire [4:0]  id_rs2    = dut.id_io.rs2;
    wire [6:0]  id_funct7 = dut.id_io.funct7;
    wire [31:0] id_imm    = dut.id_io.imm;
    wire [31:0] id_pc     = dut.id_io.pc;
    wire [31:0] if_instr  = dut.if_io.instr;
    wire        loading   = dut.if_io.loading;
    wire        halted    = dut.pc_io.halted;

    // ------------------------------------------------------------
    // Clock generation
    // ------------------------------------------------------------
    always #(CLK_PERIOD_NS / 2) clk = ~clk;

    // ------------------------------------------------------------
    // UART TX task (send one byte over the serial line)
    // Uses clock-edge counting to stay in sync with the receiver.
    // ------------------------------------------------------------
    task send_uart_byte(input [7:0] data);
        integer i;
        begin
            // Start bit
            pin_rx = 0;
            repeat (CLKS_PER_BIT) @(posedge clk);

            // Data bits (LSB first)
            for (i = 0; i < 8; i++) begin
                pin_rx = data[i];
                repeat (CLKS_PER_BIT) @(posedge clk);
            end

            // Stop bit
            pin_rx = 1;
            repeat (CLKS_PER_BIT) @(posedge clk);
        end
    endtask

    // Send an entire binary file over UART
    task send_binary_file(input string filename);
        integer fd, r;
        logic [7:0] byte_val;
        integer count;
        begin
            fd = $fopen(filename, "rb");
            if (fd == 0) begin
                $display("FATAL: Could not open %s", filename);
                $finish;
            end
            count = 0;
            while (!$feof(fd)) begin
                r = $fread(byte_val, fd);
                if (r == 1) begin
                    send_uart_byte(byte_val);
                    count++;
                end
            end
            $fclose(fd);
            $display("[TB] Sent %0d bytes from %s", count, filename);
        end
    endtask

    // ------------------------------------------------------------
    // Step the CPU one instruction and wait for it to halt
    // ------------------------------------------------------------
    task step_one;
        begin
            @(posedge clk);
            pin_step = 0;  // press (active-low)
            @(posedge clk);
            pin_step = 1;  // release
            // Wait for the step to complete (halted goes low then high)
            @(posedge clk);
            wait (halted);
            @(posedge clk);
        end
    endtask

    // ------------------------------------------------------------
    // Error tracking
    // ------------------------------------------------------------
    int errors = 0;

    task check_decode(
        input string name,
        input [6:0]  exp_opcode,
        input [4:0]  exp_rd,
        input [2:0]  exp_funct3,
        input [4:0]  exp_rs1,
        input [4:0]  exp_rs2,
        input [6:0]  exp_funct7,
        input [31:0] exp_imm
    );
        begin
            if (id_opcode !== exp_opcode || id_rd !== exp_rd || id_funct3 !== exp_funct3 ||
                id_rs1 !== exp_rs1 || id_rs2 !== exp_rs2 || id_funct7 !== exp_funct7 ||
                id_imm !== exp_imm) begin
                $display("FAIL [%s] pc=%08h", name, id_pc);
                $display("  opcode: got=%07b exp=%07b", id_opcode, exp_opcode);
                $display("  rd:     got=%0d   exp=%0d",  id_rd,     exp_rd);
                $display("  funct3: got=%03b  exp=%03b", id_funct3, exp_funct3);
                $display("  rs1:    got=%0d   exp=%0d",  id_rs1,    exp_rs1);
                $display("  rs2:    got=%0d   exp=%0d",  id_rs2,    exp_rs2);
                $display("  funct7: got=%07b  exp=%07b", id_funct7, exp_funct7);
                $display("  imm:    got=%08h  exp=%08h", id_imm,    exp_imm);
                errors++;
            end else begin
                $display("  OK  [%s] pc=%08h opcode=%07b rd=x%0d", name, id_pc, id_opcode, id_rd);
            end
        end
    endtask

    // ------------------------------------------------------------
    // Opcode constants (matching stage03_id.sv)
    // ------------------------------------------------------------
    localparam [6:0] LUI    = 7'b0110111;
    localparam [6:0] AUIPC  = 7'b0010111;
    localparam [6:0] OP_IMM = 7'b0010011;
    localparam [6:0] OP_REG = 7'b0110011;
    localparam [6:0] LOAD   = 7'b0000011;
    localparam [6:0] STORE  = 7'b0100011;

    // ------------------------------------------------------------
    // Test sequence
    // ------------------------------------------------------------
    initial begin
        $dumpfile("cpu_top_tb_dump.vcd");
        $dumpvars(0, cpu_top_tb);
        $display("=== CPU Top Testbench ===");

        // Wait for reset to deassert
        #(20 * CLK_PERIOD_NS);

        // --------------------------------------------------------
        // Phase 1: Load program via UART
        // --------------------------------------------------------
        $display("\n--- Phase 1: Loading program via UART ---");
        send_binary_file(BIN_FILE);

        // Wait for idle timeout to transition to FETCHING
        $display("[TB] Waiting for IF stage to finish loading...");
        wait (!loading);
        $display("[TB] Loading complete, CPU ready.");

        // Let the pipeline settle
        repeat (4) @(posedge clk);

        // --------------------------------------------------------
        // Phase 2: Step through instructions and verify decode
        // --------------------------------------------------------
        $display("\n--- Phase 2: Stepping through instructions ---");

        // Expected values derived from actual binary encoding (field extractions)

        //  Instr 0: lui x1, 74565  → imm = 0x00012000 (unas encodes literal value)
        step_one;
        check_decode("lui x1",    LUI,    1, 3'b010, 2, 0,  7'b0000000, 32'h00012000);

        //  Instr 1: auipc x2, 1   → imm = 0x00000000 (literal 1, bits[31:12]=0)
        step_one;
        check_decode("auipc x2",  AUIPC,  2, 3'b000, 0, 0,  7'b0000000, 32'h00000000);

        //  Instr 2: addi x1, x1, -1
        step_one;
        check_decode("addi x1,-1", OP_IMM, 1, 3'b000, 1, 31, 7'b1111111, 32'hFFFFFFFF);

        //  Instr 3: slti x3, x1, 100
        step_one;
        check_decode("slti x3",   OP_IMM, 3, 3'b010, 1, 4,  7'b0000011, 32'h00000064);

        //  Instr 4: sltiu x4, x1, 100
        step_one;
        check_decode("sltiu x4",  OP_IMM, 4, 3'b011, 1, 4,  7'b0000011, 32'h00000064);

        //  Instr 5: xori x5, x1, 1023 (0x3FF)
        step_one;
        check_decode("xori x5",   OP_IMM, 5, 3'b100, 1, 31, 7'b0011111, 32'h000003FF);

        //  Instr 6: ori x6, x1, 240 (0xF0)
        step_one;
        check_decode("ori x6",    OP_IMM, 6, 3'b110, 1, 16, 7'b0000111, 32'h000000F0);

        //  Instr 7: andi x7, x1, 15 (0xF)
        step_one;
        check_decode("andi x7",   OP_IMM, 7, 3'b111, 1, 15, 7'b0000000, 32'h0000000F);

        //  Instr 8: slli x8, x1, 4
        step_one;
        check_decode("slli x8",   OP_IMM, 8, 3'b001, 1, 4,  7'b0000000, 32'h00000004);

        //  Instr 9: srli x9, x1, 4
        step_one;
        check_decode("srli x9",   OP_IMM, 9, 3'b101, 1, 4,  7'b0000000, 32'h00000004);

        //  Instr 10: srai x10, x1, 4
        step_one;
        check_decode("srai x10",  OP_IMM, 10, 3'b101, 1, 4, 7'b0100000, 32'h00000404);

        //  Instr 11: add x11, x1, x2
        step_one;
        check_decode("add x11",   OP_REG, 11, 3'b000, 1, 2, 7'b0000000, 32'h00000000);

        //  Instr 12: sub x12, x1, x2
        step_one;
        check_decode("sub x12",   OP_REG, 12, 3'b000, 1, 2, 7'b0100000, 32'h00000000);

        //  Instr 13: sll x13, x1, x8
        step_one;
        check_decode("sll x13",   OP_REG, 13, 3'b001, 1, 8, 7'b0000000, 32'h00000000);

        //  Instr 14: slt x14, x1, x2
        step_one;
        check_decode("slt x14",   OP_REG, 14, 3'b010, 1, 2, 7'b0000000, 32'h00000000);

        //  Instr 15: sltu x15, x1, x2
        step_one;
        check_decode("sltu x15",  OP_REG, 15, 3'b011, 1, 2, 7'b0000000, 32'h00000000);

        //  Instr 16: xor x16, x1, x2
        step_one;
        check_decode("xor x16",   OP_REG, 16, 3'b100, 1, 2, 7'b0000000, 32'h00000000);

        //  Instr 17: srl x17, x1, x8
        step_one;
        check_decode("srl x17",   OP_REG, 17, 3'b101, 1, 8, 7'b0000000, 32'h00000000);

        //  Instr 18: sra x18, x1, x8
        step_one;
        check_decode("sra x18",   OP_REG, 18, 3'b101, 1, 8, 7'b0100000, 32'h00000000);

        //  Instr 19: or x19, x1, x2
        step_one;
        check_decode("or x19",    OP_REG, 19, 3'b110, 1, 2, 7'b0000000, 32'h00000000);

        //  Instr 20: and x20, x1, x2
        step_one;
        check_decode("and x20",   OP_REG, 20, 3'b111, 1, 2, 7'b0000000, 32'h00000000);

        //  Instr 21: sw x2, 4(x1)
        step_one;
        check_decode("sw x2,4",   STORE,  4,  3'b010, 1, 2, 7'b0000000, 32'h00000004);

        //  Instr 22: sh x2, 8(x1)
        step_one;
        check_decode("sh x2,8",   STORE,  8,  3'b001, 1, 2, 7'b0000000, 32'h00000008);

        //  Instr 23: sb x2, 10(x1)
        step_one;
        check_decode("sb x2,10",  STORE,  10, 3'b000, 1, 2, 7'b0000000, 32'h0000000A);

        //  Instr 24: lw x21, 4(x1)
        step_one;
        check_decode("lw x21",    LOAD,   21, 3'b010, 1, 4,  7'b0000000, 32'h00000004);

        //  Instr 25: lh x22, 8(x1)
        step_one;
        check_decode("lh x22",    LOAD,   22, 3'b001, 1, 8,  7'b0000000, 32'h00000008);

        //  Instr 26: lhu x23, 8(x1)
        step_one;
        check_decode("lhu x23",   LOAD,   23, 3'b101, 1, 8,  7'b0000000, 32'h00000008);

        //  Instr 27: lb x24, 10(x1)
        step_one;
        check_decode("lb x24",    LOAD,   24, 3'b000, 1, 10, 7'b0000000, 32'h0000000A);

        //  Instr 28: lbu x25, 10(x1)
        step_one;
        check_decode("lbu x25",   LOAD,   25, 3'b100, 1, 10, 7'b0000000, 32'h0000000A);

        //  Instr 29: addi x0, x0, 0  (nop)
        step_one;
        check_decode("nop",       OP_IMM, 0,  3'b000, 0, 0,  7'b0000000, 32'h00000000);

        // --------------------------------------------------------
        // Summary
        // --------------------------------------------------------
        $display("\n=== Test complete: %0d errors ===", errors);
        if (errors == 0) $display("ALL PASSED");
        else $display("SOME TESTS FAILED");

        #(10 * CLK_PERIOD_NS);
        $dumpflush;
        $finish;
    end

    // ------------------------------------------------------------
    // Watchdog: UART ~10ms + idle timeout ~100ms + margin
    // ------------------------------------------------------------
    initial begin
        #150ms;
        $display("FATAL: Watchdog timeout — simulation hung.");
        $dumpflush;
        $finish;
    end

endmodule
