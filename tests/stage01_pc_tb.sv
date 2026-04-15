module stagePC_tb;

    reg clk;

    stagePC_face io ();
    stagePC dut (.io);

    // 100MHz clock (10ns period)
    initial begin
        clk = 1;
        forever #5 clk = ~clk;
    end

    assign io.clk = clk;

    task automatic send_reset;
        io.reset       = 1;
        io.stall       = 0;
        io.pc_redirect = 0;
        io.pc_target   = '0;
        @(negedge io.clk);

        io.reset = 0;
    endtask

    int errors = 0;
    string last_check;

    task automatic check(input string label, input logic [31:0] got, input logic [31:0] expected);
        last_check = label;
        if (got !== expected) begin
            $display("FAIL [%s]: got 0x%08X, expected 0x%08X", label, got, expected);
            errors++;
        end else begin
            $display("PASS [%s]: 0x%08X", label, got);
        end
    endtask

    // Test Stimulus
    initial begin
        // Case 1: pc increments by 4 each cycle
        send_reset();
        for (int i = 0; i < 40; i++) begin
            check("case1_pc_next", io.pc_next, io.pc + 4);
            @(negedge io.clk);
        end
        check("case1_pc_final", io.pc, 32'd160);

        // Case 2: stall holds pc; after 16+16+16 cycles with 16 stalled, pc==32*4
        send_reset();
        repeat (16) @(negedge io.clk);
        io.stall = 1;
        repeat (16) @(negedge io.clk);
        io.stall = 0;
        repeat (16) @(negedge io.clk);
        check("case2_pc", io.pc, 32'd128);  // (16+16)*4

        // Case 3: redirect jumps to target
        send_reset();
        repeat (16) @(negedge io.clk);
        io.pc_redirect = 1;
        io.pc_target   = 32'hF000_0000;
        @(negedge io.clk);
        io.pc_redirect = 0;
        check("case3_pc", io.pc, 32'hF000_0000);

        // Case 4: redirect while stalled; stall prevents update; after stall released pc advances
        send_reset();
        repeat (10) @(negedge io.clk);
        io.pc_target   = 32'hCAFE_0000;
        io.pc_redirect = 1;
        io.stall       = 1;
        repeat (10) @(negedge io.clk);
        check("case4_pc_stalled", io.pc, 32'd40);
        // release stall and redirect together for one cycle so redirect takes effect
        io.stall = 0;
        @(negedge io.clk);
        io.pc_redirect = 0;
        repeat (16) @(negedge io.clk);
        check("case4_pc_final", io.pc, 32'hCAFE_0040);  // 0xCAFE_0000 + 16*4

        if (errors == 0) $display("-- ALL TESTS PASSED --");
        else $display("-- %0d TEST(S) FAILED --", errors);

        $finish;
    end

endmodule
