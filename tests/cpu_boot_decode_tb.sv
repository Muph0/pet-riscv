module cpu_boot_decode_tb;
    import mem_pkg::*;

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
    logic btn_step = 1; // active-low, idle = not pressed
    logic led4, led5;

    // ------------------------------------------------------------
    // Instantiate DUT
    // ------------------------------------------------------------
    cpu_top dut (
        .clk27   (clk),
        .pin_rx  (pin_rx),
        .pin_tx  (pin_tx),
        .btn_step(btn_step),
        .led4    (led4),
        .led5    (led5)
    );

    // Convenience aliases into the pipeline
    wire [31:0] id_opA       = dut.pipe.id_io.opA;
    wire [31:0] id_opB       = dut.pipe.id_io.opB;
    wire [31:0] id_op_mem    = dut.pipe.id_io.op_mem;
    wire [ 2:0] id_alu_op    = dut.pipe.id_io.alu_op;
    wire        id_negb_shar = dut.pipe.id_io.alu_negb_shar;
    wire        id_alu_mul   = dut.pipe.id_io.alu_mul;
    wire [ 1:0] id_mem_mode  = dut.pipe.id_io.mem_mode;
    wire [ 1:0] id_mem_width = dut.pipe.id_io.mem_width;
    wire [ 4:0] id_rs1       = dut.pipe.id_io.rs1;
    wire [ 4:0] id_rs2       = dut.pipe.id_io.rs2;
    wire [ 4:0] id_rd        = dut.pipe.id_io.rd;
    wire [31:0] id_pc        = dut.pipe.id_io.pc;
    wire        id_wb_en     = dut.pipe.id_io.wb_en;
    wire [31:0] if_instr     = dut.pipe.if_io.instr;
    wire        loading      = dut.bl.loading;

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
            while (!$feof(fd)) begin
                r = $fread(byte_val, fd);
                if (r == 1) fsize++;
            end
            $fclose(fd);

            send_uart_byte(8'h57);  // 'W'
            send_uart_byte(fsize[15:8]);
            send_uart_byte(fsize[7:0]);

            fd = $fopen(filename, "rb");
            count = 0;
            while (!$feof(fd)) begin
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

    // Step the CPU one instruction
    task step_one;
        begin
            send_uart_byte(8'h53);  // 'S'
            repeat (4) @(posedge clk);
        end
    endtask

    // ------------------------------------------------------------
    // Error tracking
    // ------------------------------------------------------------
    int errors = 0;

    // Check ALU-type instruction (R-type: checks rs2; I-type: skips rs2)
    task check_alu(
        input string name,
        input [ 4:0] exp_rd,
        input [ 2:0] exp_alu_op,
        input        exp_negb_shar,
        input        exp_mul,
        input [ 4:0] exp_rs1,
        input [ 4:0] exp_rs2,  // set to 5'hxx or actual for R-type
        input        check_rs2,
        input        exp_wb_en
    );
        begin
            if (id_rd !== exp_rd || id_alu_op !== exp_alu_op ||
                id_negb_shar !== exp_negb_shar || id_alu_mul !== exp_mul ||
                id_rs1 !== exp_rs1 || (check_rs2 && id_rs2 !== exp_rs2) ||
                id_wb_en !== exp_wb_en) begin
                $display("FAIL [%s] pc=%08h instr=%08h", name, id_pc, if_instr);
                $display("  rd:     got=%0d   exp=%0d",  id_rd, exp_rd);
                $display("  alu_op: got=%03b  exp=%03b", id_alu_op, exp_alu_op);
                $display("  negb:   got=%0b   exp=%0b",  id_negb_shar, exp_negb_shar);
                $display("  mul:    got=%0b   exp=%0b",  id_alu_mul, exp_mul);
                $display("  rs1:    got=%0d   exp=%0d",  id_rs1, exp_rs1);
                if (check_rs2)
                    $display("  rs2:    got=%0d   exp=%0d",  id_rs2, exp_rs2);
                $display("  wb_en:  got=%0b   exp=%0b",  id_wb_en, exp_wb_en);
                errors++;
            end else begin
                $display("  OK  [%s] pc=%08h rd=x%0d alu_op=%03b", name, id_pc, id_rd, id_alu_op);
            end
        end
    endtask

    // Check LUI/AUIPC: opA and opB carry the operands, alu_op=ADD
    task check_upper(
        input string  name,
        input [ 4:0]  exp_rd,
        input [31:0]  exp_opA,
        input [31:0]  exp_opB
    );
        begin
            if (id_rd !== exp_rd || id_opA !== exp_opA || id_opB !== exp_opB ||
                id_alu_op !== 3'b000 || id_wb_en !== 1'b1) begin
                $display("FAIL [%s] pc=%08h instr=%08h", name, id_pc, if_instr);
                $display("  rd:     got=%0d   exp=%0d",  id_rd, exp_rd);
                $display("  opA:    got=%08h  exp=%08h", id_opA, exp_opA);
                $display("  opB:    got=%08h  exp=%08h", id_opB, exp_opB);
                $display("  alu_op: got=%03b  exp=000",  id_alu_op);
                $display("  wb_en:  got=%0b   exp=1",    id_wb_en);
                errors++;
            end else begin
                $display("  OK  [%s] pc=%08h rd=x%0d opA=%08h opB=%08h",
                         name, id_pc, id_rd, id_opA, id_opB);
            end
        end
    endtask

    // Check memory instruction (don't verify rs2 — loads have imm bits there)
    task check_mem(
        input string  name,
        input [ 4:0]  exp_rd,
        input [ 4:0]  exp_rs1,
        input [ 1:0]  exp_mem_mode,
        input [ 1:0]  exp_mem_width,
        input         exp_wb_en
    );
        begin
            if (id_rd !== exp_rd || id_rs1 !== exp_rs1 ||
                id_mem_mode !== exp_mem_mode || id_mem_width !== exp_mem_width ||
                id_alu_op !== 3'b000 || id_wb_en !== exp_wb_en) begin
                $display("FAIL [%s] pc=%08h instr=%08h", name, id_pc, if_instr);
                $display("  rd:       got=%0d   exp=%0d",  id_rd, exp_rd);
                $display("  rs1:      got=%0d   exp=%0d",  id_rs1, exp_rs1);
                $display("  mem_mode: got=%02b  exp=%02b",  id_mem_mode, exp_mem_mode);
                $display("  mem_wid:  got=%02b  exp=%02b",  id_mem_width, exp_mem_width);
                $display("  wb_en:    got=%0b   exp=%0b",   id_wb_en, exp_wb_en);
                errors++;
            end else begin
                $display("  OK  [%s] pc=%08h rd=x%0d mode=%02b width=%02b",
                         name, id_pc, id_rd, id_mem_mode, id_mem_width);
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

        // Phase 2: Step through instructions and verify decode
        $display("\n--- Phase 2: Stepping through instructions ---");

        // Let the pipeline fill — one step primes the IF stage
        step_one;

        // Now each step_one advances the pipeline and we check ID output after
        // Instr 0: lui x1, 12345h  → opA=0, opB=12345000h
        step_one;
        check_upper("lui x1", 1, 32'h0, 32'h12345000);

        // Instr 1: auipc x2, 1h  → opA=PC(0x04), opB=1000h
        step_one;
        check_upper("auipc x2", 2, 32'h00000004, 32'h00001000);

        // Instr 2: addi x1, x1, -1  → I-type, alu_op=000
        step_one;
        check_alu("addi x1,-1", 1, 3'b000, 0, 0, 1, 0, 0, 1);

        // Instr 3: slti x3, x1, 100  → I-type, alu_op=010
        step_one;
        check_alu("slti x3", 3, 3'b010, 0, 0, 1, 0, 0, 1);

        // Instr 4: sltiu x4, x1, 100  → I-type, alu_op=011
        step_one;
        check_alu("sltiu x4", 4, 3'b011, 0, 0, 1, 0, 0, 1);

        // Instr 5: xori x5, x1, 1023  → I-type, alu_op=100
        step_one;
        check_alu("xori x5", 5, 3'b100, 0, 0, 1, 0, 0, 1);

        // Instr 6: ori x6, x1, 240  → I-type, alu_op=110
        step_one;
        check_alu("ori x6", 6, 3'b110, 0, 0, 1, 0, 0, 1);

        // Instr 7: andi x7, x1, 15  → I-type, alu_op=111
        step_one;
        check_alu("andi x7", 7, 3'b111, 0, 0, 1, 0, 0, 1);

        // Instr 8: slli x8, x1, 4  → I-type, alu_op=001
        step_one;
        check_alu("slli x8", 8, 3'b001, 0, 0, 1, 0, 0, 1);

        // Instr 9: srli x9, x1, 4  → I-type, alu_op=101, negb=0
        step_one;
        check_alu("srli x9", 9, 3'b101, 0, 0, 1, 0, 0, 1);

        // Instr 10: srai x10, x1, 4  → I-type, alu_op=101, negb=1
        step_one;
        check_alu("srai x10", 10, 3'b101, 1, 0, 1, 0, 0, 1);

        // Instr 11: add x11, x1, x2  → R-type, alu_op=000
        step_one;
        check_alu("add x11", 11, 3'b000, 0, 0, 1, 2, 1, 1);

        // Instr 12: sub x12, x1, x2  → R-type, alu_op=000, negb=1
        step_one;
        check_alu("sub x12", 12, 3'b000, 1, 0, 1, 2, 1, 1);

        // Instr 13: sll x13, x1, x8  → R-type, alu_op=001
        step_one;
        check_alu("sll x13", 13, 3'b001, 0, 0, 1, 8, 1, 1);

        // Instr 14: slt x14, x1, x2  → R-type, alu_op=010
        step_one;
        check_alu("slt x14", 14, 3'b010, 0, 0, 1, 2, 1, 1);

        // Instr 15: sltu x15, x1, x2  → R-type, alu_op=011
        step_one;
        check_alu("sltu x15", 15, 3'b011, 0, 0, 1, 2, 1, 1);

        // Instr 16: xor x16, x1, x2  → R-type, alu_op=100
        step_one;
        check_alu("xor x16", 16, 3'b100, 0, 0, 1, 2, 1, 1);

        // Instr 17: srl x17, x1, x8  → R-type, alu_op=101
        step_one;
        check_alu("srl x17", 17, 3'b101, 0, 0, 1, 8, 1, 1);

        // Instr 18: sra x18, x1, x8  → R-type, alu_op=101, negb=1
        step_one;
        check_alu("sra x18", 18, 3'b101, 1, 0, 1, 8, 1, 1);

        // Instr 19: or x19, x1, x2  → R-type, alu_op=110
        step_one;
        check_alu("or x19", 19, 3'b110, 0, 0, 1, 2, 1, 1);

        // Instr 20: and x20, x1, x2  → R-type, alu_op=111
        step_one;
        check_alu("and x20", 20, 3'b111, 0, 0, 1, 2, 1, 1);

        // Instr 21: sw x2, 4(x1)  → store word (rd=4 from S-type imm[4:0])
        step_one;
        check_mem("sw x2,4", 4, 1, MEM_STORE, WIDTH_32, 0);

        // Instr 22: sh x2, 8(x1)  → store half (rd=8 from S-type imm[4:0])
        step_one;
        check_mem("sh x2,8", 8, 1, MEM_STORE, WIDTH_16, 0);

        // Instr 23: sb x2, 10(x1)  → store byte (rd=10 from S-type imm[4:0])
        step_one;
        check_mem("sb x2,10", 10, 1, MEM_STORE, WIDTH_8, 0);

        // Instr 24: lw x21, 4(x1)  → load word signed
        step_one;
        check_mem("lw x21", 21, 1, MEM_LOAD_SIG, WIDTH_32, 1);

        // Instr 25: lh x22, 8(x1)  → load half signed
        step_one;
        check_mem("lh x22", 22, 1, MEM_LOAD_SIG, WIDTH_16, 1);

        // Instr 26: lhu x23, 8(x1)  → load half unsigned
        step_one;
        check_mem("lhu x23", 23, 1, MEM_LOAD_USIG, WIDTH_16, 1);

        // Instr 27: lb x24, 10(x1)  → load byte signed
        step_one;
        check_mem("lb x24", 24, 1, MEM_LOAD_SIG, WIDTH_8, 1);

        // Instr 28: lbu x25, 10(x1)  → load byte unsigned
        step_one;
        check_mem("lbu x25", 25, 1, MEM_LOAD_USIG, WIDTH_8, 1);

        // Instr 29: addi x0, x0, 0  (nop) → wb_en=0 (rd=x0)
        step_one;
        check_alu("nop", 0, 3'b000, 0, 0, 0, 0, 0, 0);

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
        $display("FATAL: Watchdog timeout — simulation hung.");
        $dumpflush;
        $finish;
    end

endmodule
