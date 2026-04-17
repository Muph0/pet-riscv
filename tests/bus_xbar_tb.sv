// =============================================================================
// bus_xbar_tb.sv - Verification testbench for bus_xbar_ctrl
//
// Test categories (from verification plan):
//   1. Reset and Configuration Initialization
//   2. Basic Routing & Connectivity
//   3. Arbitration and Priority
//   4. Stateful Locking
//   5. Boundary Conditions and Error Handling
//   6. Protocol Violations, Edge Cases, and Paranoia
// =============================================================================
`timescale 1ns / 1ps

module bus_xbar_tb;

    // =========================================================================
    // Parameters (must match DUT defaults)
    // =========================================================================
    localparam int NM = 2;
    localparam int NS = 3;

    // Address map (S_END is inclusive — last valid byte address in each region)
    localparam logic [31:0] S_START[3] = '{32'h0000_0000, 32'h1000_0000, 32'h2000_0000};
    localparam logic [31:0] S_END[3] = '{32'h0FFF_FFFF, 32'h1000_00FF, 32'h2FFF_FFFF};

    // Representative addresses inside each slave region
    localparam logic [31:0] ADDR_S0 = 32'h0000_1000;
    localparam logic [31:0] ADDR_S1 = 32'h1000_0010;
    localparam logic [31:0] ADDR_S2 = 32'h2000_1000;
    // Boundary addresses for category-5 tests
    localparam logic [31:0] ADDR_S0_LO = 32'h0000_0000;  // S_START[0]
    localparam logic [31:0] ADDR_S0_HI = 32'h0FFF_FFFF;  // S_END[0] (inclusive)
    localparam logic [31:0] ADDR_S0_OOB = 32'h1000_0000;  // S_START[1], outside S0
    localparam logic [31:0] ADDR_UNMAP = 32'h1000_0200;  // Between S1 end and S2 start

    localparam time CLK_PERIOD = 10ns;

    // =========================================================================
    // Clock and Reset
    // =========================================================================
    logic clk = 0;
    logic rst = 1;

    always #(CLK_PERIOD / 2) clk = ~clk;

    // =========================================================================
    // Interfaces
    // =========================================================================
    wishbone wb_m[NM] (
        .clk  (clk),
        .reset(rst)
    );
    wishbone wb_s[NS] (
        .clk  (clk),
        .reset(rst)
    );

    // =========================================================================
    // DUT
    // =========================================================================
    bus_xbar_ctrl #(
        .NM     (NM),
        .NS     (NS),
        .S_START(S_START),
        .S_END  (S_END)
    ) dut (
        .m_bus(wb_m),
        .s_bus(wb_s)
    );

    // =========================================================================
    // Category 3.2 submodule - 3-master priority cascade
    // =========================================================================
    logic sub3_rst = 1'b1;  // held high until test_3_arbitration reaches 3.2
    logic sub3_done;
    int sub3_p, sub3_f;

    bus_xbar_3m_sub sub3 (
        .clk (clk),
        .rst (sub3_rst),
        .done(sub3_done),
        .p3  (sub3_p),
        .f3  (sub3_f)
    );

    // =========================================================================
    // Test bookkeeping
    // =========================================================================
    int pass_count = 0;
    int fail_count = 0;

    task automatic check(string name, logic cond);
        if (cond) begin
            $display("  [PASS] %s", name);
            pass_count++;
        end else begin
            $display("  [FAIL] %s", name);
            fail_count++;
        end
    endtask

    // Advance n clock cycles and settle 1 ns after the last rising edge
    task automatic tick(int n = 1);
        repeat (n) @(posedge clk);
        #1;
    endtask

    // =========================================================================
    // Bus helpers
    // =========================================================================
    task automatic idle_masters();
        wb_m[0].adr  = '0;
        wb_m[0].mtos = '0;
        wb_m[0].sel  = '0;
        wb_m[0].we   = 0;
        wb_m[0].cyc  = 0;
        wb_m[0].stb  = 0;
        wb_m[1].adr  = '0;
        wb_m[1].mtos = '0;
        wb_m[1].sel  = '0;
        wb_m[1].we   = 0;
        wb_m[1].cyc  = 0;
        wb_m[1].stb  = 0;
    endtask

    task automatic idle_slaves();
        wb_s[0].stom = '0;
        wb_s[0].ack  = 0;
        wb_s[0].err  = 0;
        wb_s[0].rty  = 0;
        wb_s[1].stom = '0;
        wb_s[1].ack  = 0;
        wb_s[1].err  = 0;
        wb_s[1].rty  = 0;
        wb_s[2].stom = '0;
        wb_s[2].ack  = 0;
        wb_s[2].err  = 0;
        wb_s[2].rty  = 0;
    endtask

    task automatic full_idle();
        idle_masters();
        idle_slaves();
    endtask

    // De-assert reset with clean bus state
    task automatic apply_reset(int cycles = 4);
        full_idle();
        rst = 1;
        tick(cycles);
        @(negedge clk);
        rst = 0;
        #1;
    endtask

    // =========================================================================
    // Category 1 - Reset and Configuration Initialization
    // =========================================================================
    task automatic test_1_reset();
        $display("\n--- Category 1: Reset and Configuration ---");

        // 1.1 Cold Reset: s_busy and s_owner must all be zero after rst
        apply_reset();
        check("1.1 Cold reset: s_busy[0] = 0", dut.s_busy[0] === 1'b0);
        check("1.1 Cold reset: s_busy[1] = 0", dut.s_busy[1] === 1'b0);
        check("1.1 Cold reset: s_busy[2] = 0", dut.s_busy[2] === 1'b0);
        check("1.1 Cold reset: s_owner[0] = 0", dut.s_owner[0] === 0);
        check("1.1 Cold reset: s_owner[1] = 0", dut.s_owner[1] === 0);
        check("1.1 Cold reset: s_owner[2] = 0", dut.s_owner[2] === 0);

        // 1.2 Reset path isolation: all outputs stay at 0 while rst=1
        rst = 1;
        tick(2);
        check("1.2 Reset isolation: m0.stom = 0", wb_m[0].stom === '0);
        check("1.2 Reset isolation: m0.ack  = 0", wb_m[0].ack === 1'b0);
        check("1.2 Reset isolation: m0.err  = 0", wb_m[0].err === 1'b0);
        check("1.2 Reset isolation: m0.rty  = 0", wb_m[0].rty === 1'b0);
        check("1.2 Reset isolation: m1.stom = 0", wb_m[1].stom === '0);
        check("1.2 Reset isolation: s0.adr  = 0", wb_s[0].adr === '0);
        check("1.2 Reset isolation: s0.cyc  = 0", wb_s[0].cyc === 1'b0);
        check("1.2 Reset isolation: s0.stb  = 0", wb_s[0].stb === 1'b0);
        check("1.2 Reset isolation: s1.cyc  = 0", wb_s[1].cyc === 1'b0);
        check("1.2 Reset isolation: s2.cyc  = 0", wb_s[2].cyc === 1'b0);
        @(negedge clk);
        rst = 0;
        #1;

        // 1.3 / 1.4: Overlap and invalid-range checks are elaboration-time $error
        //            assertions. The separate modules bus_xbar_bad_overlap_tb and
        //            bus_xbar_invalid_range_tb (below) exercise those paths and
        //            are expected to emit $error messages when simulated.
        $display("  [NOTE] 1.3/1.4: See bus_xbar_bad_overlap_tb / bus_xbar_invalid_range_tb");
    endtask

    // =========================================================================
    // Category 2 - Basic Routing & Connectivity
    // =========================================================================
    task automatic test_2_routing();
        logic [31:0] walking;
        $display("\n--- Category 2: Basic Routing & Connectivity ---");

        // ------------------------------------------------------------------
        // 2.1  Forward Path Integrity - walking-1 / walking-0 on all fields
        // ------------------------------------------------------------------
        apply_reset();
        // Lock M0 → S0
        wb_m[0].cyc = 1;
        wb_m[0].adr = ADDR_S0;
        tick(1);  // s_busy[0] registered on this edge

        walking = 32'h0000_0001;
        repeat (32) begin
            @(negedge clk);
            wb_m[0].mtos = walking;
            wb_m[0].sel  = walking[3:0];
            wb_m[0].we   = walking[0];
            wb_m[0].stb  = 1'b1;
            #1;
            check("2.1 Fwd walking-1: s0.mtos == m0.mtos", wb_s[0].mtos === wb_m[0].mtos);
            check("2.1 Fwd walking-1: s0.sel  == m0.sel", wb_s[0].sel === wb_m[0].sel);
            check("2.1 Fwd walking-1: s0.we   == m0.we", wb_s[0].we === wb_m[0].we);
            check("2.1 Fwd walking-1: s0.stb  == m0.stb", wb_s[0].stb === wb_m[0].stb);
            check("2.1 Fwd walking-1: s0.cyc  = 1", wb_s[0].cyc === 1'b1);
            // No cross-talk to adjacent slaves
            check("2.1 No crosstalk: s1.adr = 0", wb_s[1].adr === '0);
            check("2.1 No crosstalk: s1.cyc = 0", wb_s[1].cyc === 1'b0);
            check("2.1 No crosstalk: s2.cyc = 0", wb_s[2].cyc === 1'b0);
            walking = walking << 1;
        end

        // walking-0 check
        @(negedge clk);
        wb_m[0].mtos = 32'hFFFF_FFFE;
        #1;
        check("2.1 Fwd walking-0: s0.mtos = 0xFFFFFFFE", wb_s[0].mtos === 32'hFFFF_FFFE);
        full_idle();
        tick(2);

        // ------------------------------------------------------------------
        // 2.2  Return Path Integrity - walking-1 on slave return fields
        // ------------------------------------------------------------------
        apply_reset();
        wb_m[0].cyc = 1;
        wb_m[0].adr = ADDR_S0;
        wb_m[0].stb = 1;
        tick(1);

        walking = 32'h0000_0001;
        repeat (32) begin
            @(negedge clk);
            wb_s[0].stom = walking;
            wb_s[0].ack  = walking[0];
            wb_s[0].err  = walking[1];
            #1;
            check("2.2 Ret walking-1: m0.stom == s0.stom", wb_m[0].stom === wb_s[0].stom);
            check("2.2 Ret walking-1: m0.ack  == s0.ack", wb_m[0].ack === wb_s[0].ack);
            check("2.2 Ret walking-1: m0.err  == s0.err", wb_m[0].err === wb_s[0].err);
            walking = walking << 1;
        end
        full_idle();
        tick(2);

        // ------------------------------------------------------------------
        // 2.3  Unmapped Master Isolation: M1 return signals silent while M0 owns S0
        // ------------------------------------------------------------------
        apply_reset();
        wb_m[0].cyc  = 1;
        wb_m[0].adr  = ADDR_S0;
        wb_m[0].stb  = 1;
        wb_s[0].stom = 32'hDEAD_BEEF;
        wb_s[0].ack  = 1;
        tick(1);
        check("2.3 M1 isolated: m1.stom = 0", wb_m[1].stom === '0);
        check("2.3 M1 isolated: m1.ack  = 0", wb_m[1].ack === 1'b0);
        check("2.3 M1 isolated: m1.err  = 0", wb_m[1].err === 1'b0);
        check("2.3 M1 isolated: m1.rty  = 0", wb_m[1].rty === 1'b0);
        full_idle();
        tick(2);

        // ------------------------------------------------------------------
        // 2.4  Unmapped Slave Isolation: slaves not targeted are zeroed
        // ------------------------------------------------------------------
        apply_reset();
        wb_m[0].cyc  = 1;
        wb_m[0].adr  = ADDR_S0;
        wb_m[0].stb  = 1;
        wb_m[0].mtos = 32'hCAFE_BABE;
        tick(1);
        check("2.4 S1 isolated: adr  = 0", wb_s[1].adr === '0);
        check("2.4 S1 isolated: mtos = 0", wb_s[1].mtos === '0);
        check("2.4 S1 isolated: cyc  = 0", wb_s[1].cyc === 1'b0);
        check("2.4 S1 isolated: stb  = 0", wb_s[1].stb === 1'b0);
        check("2.4 S2 isolated: adr  = 0", wb_s[2].adr === '0);
        check("2.4 S2 isolated: cyc  = 0", wb_s[2].cyc === 1'b0);
        full_idle();
        tick(2);

        // ------------------------------------------------------------------
        // 2.5  Parallel Non-Blocking Traffic: M0→S0 and M1→S1 same cycle
        // ------------------------------------------------------------------
        apply_reset();
        @(negedge clk);
        wb_m[0].cyc  = 1;
        wb_m[0].adr  = ADDR_S0;
        wb_m[0].stb  = 1;
        wb_m[0].mtos = 32'hAAAA_AAAA;
        wb_m[1].cyc  = 1;
        wb_m[1].adr  = ADDR_S1;
        wb_m[1].stb  = 1;
        wb_m[1].mtos = 32'h5555_5555;
        tick(1);
        check("2.5 Parallel: s0.cyc  = 1", wb_s[0].cyc === 1'b1);
        check("2.5 Parallel: s1.cyc  = 1", wb_s[1].cyc === 1'b1);
        check("2.5 Parallel: s0.mtos = M0 data", wb_s[0].mtos === 32'hAAAA_AAAA);
        check("2.5 Parallel: s1.mtos = M1 data", wb_s[1].mtos === 32'h5555_5555);
        check("2.5 Parallel: s0.adr  = M0 addr", wb_s[0].adr === ADDR_S0);
        check("2.5 Parallel: s1.adr  = M1 addr", wb_s[1].adr === ADDR_S1);
        check("2.5 Parallel: s_owner[0] = 0", dut.s_owner[0] === 0);
        check("2.5 Parallel: s_owner[1] = 1", dut.s_owner[1] === 1);
        full_idle();
        tick(2);
    endtask

    // =========================================================================
    // Category 3 - Arbitration and Priority
    // =========================================================================
    task automatic test_3_arbitration();
        $display("\n--- Category 3: Arbitration & Priority ---");

        // ------------------------------------------------------------------
        // 3.1  Simultaneous Contention: both masters request S0 together - M0 wins
        // ------------------------------------------------------------------
        apply_reset();
        @(negedge clk);
        wb_m[0].cyc = 1;
        wb_m[0].adr = ADDR_S0;
        wb_m[1].cyc = 1;
        wb_m[1].adr = ADDR_S0;
        tick(1);
        check("3.1 Contention: s_busy[0] = 1", dut.s_busy[0] === 1'b1);
        check("3.1 Contention: M0 wins", dut.s_owner[0] === 0);
        // M1 must receive a combinatorial rty
        check("3.1 Contention: M1 gets rty", wb_m[1].rty === 1'b1);
        check("3.1 Contention: M1 no ack", wb_m[1].ack === 1'b0);
        full_idle();
        tick(2);

        // ------------------------------------------------------------------
        // 3.3  Priority Re-evaluation: M0 drops cyc → M1 wins on next cycle
        // ------------------------------------------------------------------
        apply_reset();
        @(negedge clk);
        wb_m[0].cyc = 1;
        wb_m[0].adr = ADDR_S0;
        wb_m[1].cyc = 1;
        wb_m[1].adr = ADDR_S0;
        tick(1);  // M0 wins

        @(negedge clk);
        wb_m[0].cyc = 0;  // M0 releases
        tick(2);  // cycle 1: s_busy cleared; cycle 2: M1 arbitrated in
        check("3.3 Re-eval: S0 re-locked", dut.s_busy[0] === 1'b1);
        check("3.3 Re-eval: M1 wins", dut.s_owner[0] === 1);
        full_idle();
        tick(2);

        // ------------------------------------------------------------------
        // 3.4  Lowest priority master wins when it is the only requester
        // ------------------------------------------------------------------
        apply_reset();
        @(negedge clk);
        wb_m[1].cyc = 1;
        wb_m[1].adr = ADDR_S0;  // Only M1
        tick(1);
        check("3.4 Low-priority grant: M1 wins", dut.s_busy[0] === 1'b1);
        check("3.4 Low-priority grant: owner=1", dut.s_owner[0] === 1);
        full_idle();
        tick(2);

        // ------------------------------------------------------------------
        // 3.2  Priority Cascade - executed via 3-master submodule
        // ------------------------------------------------------------------
        $display("\n--- Category 3.2: Priority Cascade (3-master submodule) ---");
        sub3_rst = 1'b0;  // release: submodule's initial block wakes up
        wait (sub3_done);  // block until submodule reports completion
        #1;
        pass_count += sub3_p;
        fail_count += sub3_f;
        sub3_rst = 1'b1;  // re-hold
    endtask

    // =========================================================================
    // Category 4 - Stateful Locking
    // =========================================================================
    task automatic test_4_locking();
        $display("\n--- Category 4: Stateful Locking ---");

        // ------------------------------------------------------------------
        // 4.1  Lower-priority master holds lock; higher-priority arrives late
        // ------------------------------------------------------------------
        apply_reset();
        @(negedge clk);
        wb_m[1].cyc = 1;
        wb_m[1].adr = ADDR_S0;  // M1 wins while M0 is idle
        tick(1);
        check("4.1 Pre-contention: M1 owns S0", dut.s_busy[0] === 1'b1 && dut.s_owner[0] === 1);

        @(negedge clk);
        wb_m[0].cyc = 1;
        wb_m[0].adr = ADDR_S0;  // M0 now wants S0 too
        #1;
        check("4.1 Lock held: s_owner still 1", dut.s_owner[0] === 1);
        check("4.1 Lock held: M0 gets rty", wb_m[0].rty === 1'b1);
        check("4.1 Lock held: M1 no rty", wb_m[1].rty === 1'b0);
        full_idle();
        tick(2);

        // ------------------------------------------------------------------
        // 4.2  Burst lock: M1 holds 20 cycles with toggling stb; M0 requests
        //      from cycle 10 and must be continuously denied
        // ------------------------------------------------------------------
        apply_reset();
        @(negedge clk);
        wb_m[1].cyc = 1;
        wb_m[1].adr = ADDR_S0;
        wb_m[1].stb = 1;
        tick(1);  // M1 locks

        repeat (9) begin
            @(negedge clk);
            wb_m[1].stb = ~wb_m[1].stb;
            tick(1);
        end

        @(negedge clk);
        wb_m[0].cyc = 1;
        wb_m[0].adr = ADDR_S0;  // M0 arrives at cycle 10
        repeat (10) begin
            tick(1);
            check("4.2 Burst: M1 still owns S0", dut.s_owner[0] === 1);
            check("4.2 Burst: M0 gets rty", wb_m[0].rty === 1'b1);
        end
        full_idle();
        tick(2);

        // ------------------------------------------------------------------
        // 4.3  Clean Release: s_busy goes low on the cycle after cyc drops
        // ------------------------------------------------------------------
        apply_reset();
        @(negedge clk);
        wb_m[1].cyc = 1;
        wb_m[1].adr = ADDR_S0;
        tick(1);
        check("4.3 Pre-release: s_busy[0] = 1", dut.s_busy[0] === 1'b1);

        @(negedge clk);
        wb_m[1].cyc = 0;
        tick(1);
        check("4.3 Post-release: s_busy[0] = 0", dut.s_busy[0] === 1'b0);
        full_idle();
        tick(2);
    endtask

    // =========================================================================
    // Category 5 - Boundary Conditions and Error Handling
    // =========================================================================
    task automatic test_5_boundaries();
        $display("\n--- Category 5: Boundary Conditions & Error Handling ---");

        // 5.1  Lower boundary of S0 maps to S0
        apply_reset();
        @(negedge clk);
        wb_m[0].cyc = 1;
        wb_m[0].adr = ADDR_S0_LO;
        tick(1);
        check("5.1 Lower boundary: maps to S0", dut.s_busy[0] === 1'b1);
        check("5.1 Lower boundary: owner = 0", dut.s_owner[0] === 0);
        full_idle();
        tick(2);

        // 5.2  Upper boundary of S0 (S_END[0]-1) maps to S0
        apply_reset();
        @(negedge clk);
        wb_m[0].cyc = 1;
        wb_m[0].adr = ADDR_S0_HI;
        tick(1);
        check("5.2 Upper boundary: maps to S0", dut.s_busy[0] === 1'b1);
        check("5.2 Upper boundary: owner = 0", dut.s_owner[0] === 0);
        full_idle();
        tick(2);

        // 5.3  S_END[0] == S_START[1] - must NOT map to S0; maps to S1
        apply_reset();
        @(negedge clk);
        wb_m[0].cyc = 1;
        wb_m[0].adr = ADDR_S0_OOB;
        tick(1);
        check("5.3 OOB: NOT routed to S0", !(dut.s_busy[0] && dut.s_owner[0] === 0));
        check("5.3 OOB: routed to S1", dut.s_busy[1] === 1'b1 && dut.s_owner[1] === 0);
        full_idle();
        tick(2);

        // 5.4  Unmapped address + stb → combinatorial err, no ack, no rty
        apply_reset();
        @(negedge clk);
        wb_m[0].cyc = 1;
        wb_m[0].adr = ADDR_UNMAP;
        wb_m[0].stb = 1;
        #1;
        check("5.4 Unmapped+stb: err asserted", wb_m[0].err === 1'b1);
        check("5.4 Unmapped+stb: no ack", wb_m[0].ack === 1'b0);
        check("5.4 Unmapped+stb: no rty", wb_m[0].rty === 1'b0);
        full_idle();
        tick(2);

        // 5.5  Unmapped address without stb → err must NOT be asserted
        apply_reset();
        @(negedge clk);
        wb_m[0].cyc = 1;
        wb_m[0].adr = ADDR_UNMAP;
        wb_m[0].stb = 0;
        #1;
        check("5.5 Unmapped no stb: no err", wb_m[0].err === 1'b0);
        check("5.5 Unmapped no stb: no ack", wb_m[0].ack === 1'b0);
        full_idle();
        tick(2);
    endtask

    // =========================================================================
    // Category 6 - Protocol Violations, Edge Cases, and Paranoia
    // =========================================================================
    task automatic test_6_edge_cases();
        $display("\n--- Category 6: Edge Cases & Protocol Violations ---");

        // ------------------------------------------------------------------
        // 6.1  Mid-Cycle Address Mutiny: M0 keeps cyc high and changes address
        //      to S1 after locking S0. The forward MUX still routes to S0.
        //      The return MUX now targets S1 (unowned) → M0 must get rty,
        //      not S0's ack.
        // ------------------------------------------------------------------
        apply_reset();
        @(negedge clk);
        wb_m[0].cyc = 1;
        wb_m[0].adr = ADDR_S0;
        tick(2);  // S0 locked

        @(negedge clk);
        wb_m[0].adr = ADDR_S1;  // Address mutiny - cyc stays high
        wb_s[0].ack = 1;  // S0 slave responds (but M0 no longer targets it)
        #1;
        check("6.1 Address mutiny: S0 still locked by M0",
              dut.s_busy[0] === 1'b1 && dut.s_owner[0] === 0);
        // target[0] is now 1 (S1), s_busy[1]=0 → master gets rty, not S0's ack
        check("6.1 Address mutiny: M0 does not see S0 ack", wb_m[0].ack === 1'b0);
        wb_s[0].ack = 0;
        full_idle();
        tick(2);

        // ------------------------------------------------------------------
        // 6.2  Zero-Cycle Pulse: M0 drops cyc one cycle after winning arbitration
        // ------------------------------------------------------------------
        apply_reset();
        @(negedge clk);
        wb_m[0].cyc = 1;
        wb_m[0].adr = ADDR_S0;
        tick(1);  // Lock acquired

        @(negedge clk);
        wb_m[0].cyc = 0;  // Immediately release
        tick(1);
        check("6.2 Zero-pulse: lock released cycle+1", dut.s_busy[0] === 1'b0);
        tick(2);
        check("6.2 Zero-pulse: S0 stays idle afterwards", dut.s_busy[0] === 1'b0);
        full_idle();
        tick(2);

        // ------------------------------------------------------------------
        // 6.3  Spurious Slave Response: S0 drives ack while it has no owner
        // ------------------------------------------------------------------
        apply_reset();
        @(negedge clk);
        wb_s[0].ack  = 1;
        wb_s[0].stom = 32'hDEAD_BEEF;
        #1;
        check("6.3 Rogue ack: M0 does not receive ack", wb_m[0].ack === 1'b0);
        check("6.3 Rogue ack: M0 stom shielded", wb_m[0].stom === '0);
        check("6.3 Rogue ack: M1 does not receive ack", wb_m[1].ack === 1'b0);
        wb_s[0].ack = 0;
        full_idle();
        tick(2);

        // ------------------------------------------------------------------
        // 6.4  Mid-Transaction Reset: rst kills all locks and silences outputs
        // ------------------------------------------------------------------
        apply_reset();
        @(negedge clk);
        wb_m[0].cyc = 1;
        wb_m[0].adr = ADDR_S0;
        wb_m[0].stb = 1;
        wb_m[1].cyc = 1;
        wb_m[1].adr = ADDR_S1;
        wb_m[1].stb = 1;
        tick(2);
        check("6.4 Pre-reset: S0 locked", dut.s_busy[0] === 1'b1);
        check("6.4 Pre-reset: S1 locked", dut.s_busy[1] === 1'b1);

        rst = 1;
        tick(1);
        check("6.4 Mid-tx reset: s_busy[0] = 0", dut.s_busy[0] === 1'b0);
        check("6.4 Mid-tx reset: s_busy[1] = 0", dut.s_busy[1] === 1'b0);
        check("6.4 Mid-tx reset: m0.ack    = 0", wb_m[0].ack === 1'b0);
        check("6.4 Mid-tx reset: m1.ack    = 0", wb_m[1].ack === 1'b0);
        @(negedge clk);
        rst = 0;
        #1;
        full_idle();
        tick(2);

        // ------------------------------------------------------------------
        // 6.5  Constrained-Random Stress (1 000 cycles)
        //      Monitor for: multiply-driven outputs, deadlocks, starvation
        // ------------------------------------------------------------------
        apply_reset();
        begin
            automatic int          deadlock_ctr   [NS];
            automatic int          ack_total      [NM];
            automatic int          errors_6_5 = 0;
            automatic logic [31:0] slave_addrs    [NS] = '{ADDR_S0, ADDR_S1, ADDR_S2};

            for (int i = 0; i < NS; i++) deadlock_ctr[i] = 0;
            for (int i = 0; i < NM; i++) ack_total[i] = 0;

            repeat (1000) begin
                @(negedge clk);
                // Random master behaviour (NM=2, unrolled)
                wb_m[0].cyc  = ($urandom_range(0, 3) > 0);
                wb_m[0].adr  = slave_addrs[$urandom_range(0, NS-1)];
                wb_m[0].stb  = wb_m[0].cyc & $urandom_range(0, 1);
                wb_m[0].mtos = $urandom();
                wb_m[0].sel  = 4'b1111;
                wb_m[0].we   = $urandom_range(0, 1);
                wb_m[1].cyc  = ($urandom_range(0, 3) > 0);
                wb_m[1].adr  = slave_addrs[$urandom_range(0, NS-1)];
                wb_m[1].stb  = wb_m[1].cyc & $urandom_range(0, 1);
                wb_m[1].mtos = $urandom();
                wb_m[1].sel  = 4'b1111;
                wb_m[1].we   = $urandom_range(0, 1);
                // Random slave responses (NS=3, unrolled)
                wb_s[0].ack  = $urandom_range(0, 1);
                wb_s[0].stom = $urandom();
                wb_s[1].ack  = $urandom_range(0, 1);
                wb_s[1].stom = $urandom();
                wb_s[2].ack  = $urandom_range(0, 1);
                wb_s[2].stom = $urandom();

                tick(1);

                // --- Deadlock monitor (NS=3, NM=2, unrolled) ---
                // Slave 0
                if (dut.s_busy[0] && !(dut.s_owner[0] == 0 ? wb_m[0].cyc : wb_m[1].cyc))
                    deadlock_ctr[0]++;
                else deadlock_ctr[0] = 0;
                // Slave 1
                if (dut.s_busy[1] && !(dut.s_owner[1] == 0 ? wb_m[0].cyc : wb_m[1].cyc))
                    deadlock_ctr[1]++;
                else deadlock_ctr[1] = 0;
                // Slave 2
                if (dut.s_busy[2] && !(dut.s_owner[2] == 0 ? wb_m[0].cyc : wb_m[1].cyc))
                    deadlock_ctr[2]++;
                else deadlock_ctr[2] = 0;

                for (int s = 0; s < NS; s++) begin
                    if (deadlock_ctr[s] > 200) begin
                        $display(
                            "  [FAIL] 6.5 Deadlock: Slave %0d locked without owner for >200 cycles",
                            s);
                        errors_6_5++;
                        deadlock_ctr[s] = 0;
                    end
                end

                // Track ack totals (NM=2, unrolled)
                if (wb_m[0].ack) ack_total[0]++;
                if (wb_m[1].ack) ack_total[1]++;
            end

            full_idle();
            tick(4);
            check("6.5 Stress: no deadlock detected", errors_6_5 === 0);
            $display("  [INFO] 6.5 Stress complete. ACKs received: M0=%0d M1=%0d", ack_total[0],
                     ack_total[1]);
        end

    endtask

    // =========================================================================
    // Main test sequence
    // =========================================================================
    initial begin
        $dumpfile("bus_xbar_tb.fst");
        $dumpvars(0, bus_xbar_tb);

        $display("===========================================");
        $display("  bus_xbar_ctrl Verification Testbench    ");
        $display("===========================================");

        test_1_reset();
        test_2_routing();
        test_3_arbitration();
        test_4_locking();
        test_5_boundaries();
        test_6_edge_cases();

        $display("\n===========================================");
        $display("  RESULT: %0d PASSED, %0d FAILED", pass_count, fail_count);
        if (fail_count == 0) $display("  ALL TESTS PASSED");
        else $display("  SOME TESTS FAILED");
        $display("===========================================");

        $finish;
    end

endmodule


// =============================================================================
// 1.3  Overlap Detection: instantiate with overlapping slave ranges.
//      Expect: $error "XBAR CONFIG ERROR: Overlap between Slave 0 ... Slave 1"
// =============================================================================
module bus_xbar_bad_overlap_tb;
    logic clk = 0, rst = 0;
    wishbone wb_m[1] (
        .clk  (clk),
        .reset(rst)
    );
    wishbone wb_s[2] (
        .clk  (clk),
        .reset(rst)
    );

    // S0=[0x000, 0x200), S1=[0x100, 0x300) - deliberate overlap
    bus_xbar_ctrl #(
        .NM     (1),
        .NS     (2),
        .S_START('{32'h0000_0000, 32'h0000_0100}),
        .S_END  ('{32'h0000_0200, 32'h0000_0300})
    ) dut_overlap (
        .m_bus(wb_m),
        .s_bus(wb_s)
    );

    initial begin
        $display("[1.3] bus_xbar_bad_overlap_tb: expect $error about overlapping ranges.");
        #10 $finish;
    end
endmodule


// =============================================================================
// 1.4  Invalid Range Detection: S_START[0] > S_END[0].
//      Expect: $error "XBAR CONFIG ERROR: Slave 0 has invalid range"
// =============================================================================
module bus_xbar_invalid_range_tb;
    logic clk = 0, rst = 0;
    wishbone wb_m[1] (
        .clk  (clk),
        .reset(rst)
    );
    wishbone wb_s[1] (
        .clk  (clk),
        .reset(rst)
    );

    // S_START > S_END: invalid
    bus_xbar_ctrl #(
        .NM     (1),
        .NS     (1),
        .S_START('{32'h0000_1000}),
        .S_END  ('{32'h0000_0000})
    ) dut_invalid (
        .m_bus(wb_m),
        .s_bus(wb_s)
    );

    initial begin
        $display("[1.4] bus_xbar_invalid_range_tb: expect $error about invalid range.");
        #10 $finish;
    end
endmodule


// =============================================================================
// 3.2  Priority Cascade - submodule driven by bus_xbar_tb.
//
// clk/rst are inputs: the parent (bus_xbar_tb) controls timing.
// done goes high when all assertions are complete; the parent collects
// p3/f3 into its global counters, then re-asserts rst to quiesce this module.
// =============================================================================
module bus_xbar_3m_sub (
    input  logic clk,
    input  logic rst,   // active-high; hold 1 until test should run
    output logic done,  // goes 1 when assertions are finished
    output int   p3,    // assertion pass count
    output int   f3     // assertion fail count
);
    localparam logic [31:0] S_START3[2] = '{32'h0000_0000, 32'h2000_0000};
    localparam logic [31:0] S_END3[2] = '{32'h1000_0000, 32'h3000_0000};

    wishbone wb_m[3] (
        .clk  (clk),
        .reset(rst)
    );
    wishbone wb_s[2] (
        .clk  (clk),
        .reset(rst)
    );

    bus_xbar_ctrl #(
        .NM     (3),
        .NS     (2),
        .S_START(S_START3),
        .S_END  (S_END3)
    ) dut3 (
        .m_bus(wb_m),
        .s_bus(wb_s)
    );

    task automatic chk3(string name, logic cond);
        if (cond) begin
            $display("  [PASS] %s", name);
            p3++;
        end else begin
            $display("  [FAIL] %s", name);
            f3++;
        end
    endtask

    initial begin
        done = 0;
        p3 = 0;
        f3 = 0;

        // Idle buses while parent holds reset high (unrolled - constant indices)
        wb_m[0].adr = '0;
        wb_m[0].mtos = '0;
        wb_m[0].sel = '0;
        wb_m[0].we = 0;
        wb_m[0].cyc = 0;
        wb_m[0].stb = 0;
        wb_m[1].adr = '0;
        wb_m[1].mtos = '0;
        wb_m[1].sel = '0;
        wb_m[1].we = 0;
        wb_m[1].cyc = 0;
        wb_m[1].stb = 0;
        wb_m[2].adr = '0;
        wb_m[2].mtos = '0;
        wb_m[2].sel = '0;
        wb_m[2].we = 0;
        wb_m[2].cyc = 0;
        wb_m[2].stb = 0;
        wb_s[0].stom = '0;
        wb_s[0].ack = 0;
        wb_s[0].err = 0;
        wb_s[0].rty = 0;
        wb_s[1].stom = '0;
        wb_s[1].ack = 0;
        wb_s[1].err = 0;
        wb_s[1].rty = 0;

        // Block until parent signals "go" by deasserting rst
        wait (rst === 1'b0);
        #1;

        // All three masters simultaneously request Slave 0 on the same edge
        @(negedge clk);
        wb_m[0].cyc = 1;
        wb_m[0].adr = 32'h0000_1000;
        wb_m[1].cyc = 1;
        wb_m[1].adr = 32'h0000_1000;
        wb_m[2].cyc = 1;
        wb_m[2].adr = 32'h0000_1000;
        @(posedge clk);
        #1;

        chk3("3.2 Priority cascade: M0 wins", dut3.s_owner[0] === 0);
        chk3("3.2 Priority cascade: M1 gets rty", wb_m[1].rty === 1'b1);
        chk3("3.2 Priority cascade: M2 gets rty", wb_m[2].rty === 1'b1);
        chk3("3.2 Priority cascade: M1 no ack", wb_m[1].ack === 1'b0);
        chk3("3.2 Priority cascade: M2 no ack", wb_m[2].ack === 1'b0);

        done = 1'b1;  // signal parent: results ready in p3/f3
    end

endmodule
