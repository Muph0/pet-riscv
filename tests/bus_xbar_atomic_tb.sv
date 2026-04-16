// =============================================================================
// bus_xbar_atomic_tb.sv — 5-master atomic read-modify-write stress test
//
// Topology : NM=5 masters / NS=1 slave (single 32-bit register at REG_ADDR)
//
// Each master repeatedly executes the following sequence
// (keeping CYC high across both read and write — the crossbar lock
//  prevents any other master from interleaving):
//
//   1. Assert CYC  (grab the bus lock)
//   2. READ  the register             (cyc=1, stb=1, we=0 → wait ack)
//   3. WRITE back value + prime_i     (cyc=1, stb=1, we=1 → wait ack)
//   4. Deassert CYC (release lock)
//   5. Wait prime_i clock cycles
//   6. Repeat N_ITER times
//
// Because CYC is held for the entire RMW, the operation is atomic.
//
// Expected final register value (all iterations complete):
//   N_ITER × (P0 + P1 + P2 + P3 + P4) = 20 × (17+13+11+7+5) = 20 × 53 = 1060
// =============================================================================
`timescale 1ns/1ps

// ---------------------------------------------------------------------------
// Simple zero-wait-state Wishbone slave with one 32-bit register.
//   - ack is asserted combinatorially (zero latency)
//   - register is written on every posedge where cyc & stb & we
//   - register is always readable on stom
// ---------------------------------------------------------------------------
module wb_reg_slave (
    wishbone.slave bus
);
    logic [31:0] reg_val = '0;

    // Combinatorial read and acknowledge
    assign bus.stom = reg_val;
    assign bus.ack  = bus.cyc & bus.stb;
    assign bus.err  = 1'b0;
    assign bus.rty  = 1'b0;

    // Registered write
    always_ff @(posedge bus.clk) begin
        if (bus.rst)
            reg_val <= '0;
        else if (bus.cyc & bus.stb & bus.we)
            reg_val <= bus.mtos;
    end

endmodule


// ---------------------------------------------------------------------------
// Top-level testbench
// ---------------------------------------------------------------------------
module bus_xbar_atomic_tb;

    // =========================================================================
    // Parameters
    // =========================================================================
    localparam int NM = 5;
    localparam int NS = 1;
    localparam logic [31:0] S_START_A[1] = '{32'h0000_0000};
    localparam logic [31:0] S_END_A  [1] = '{32'h2000_0000};

    localparam logic [31:0] REG_ADDR = 32'h0000_1000;

    localparam int N_ITER = 20;   // iterations per master

    // Prime numbers — each master adds its own to the shared register
    localparam int P0 = 17;
    localparam int P1 = 13;
    localparam int P2 = 11;
    localparam int P3 =  7;
    localparam int P4 =  5;

    // With perfect atomicity every increment is preserved:
    //   final = N_ITER × (P0+P1+P2+P3+P4) = 20 × 53 = 1060
    localparam int EXPECTED = N_ITER * (P0 + P1 + P2 + P3 + P4);

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
    wishbone wb_m[NM] (.clk(clk), .rst(rst));
    wishbone wb_s[NS] (.clk(clk), .rst(rst));

    // =========================================================================
    // DUT — Crossbar
    // =========================================================================
    bus_xbar_ctrl #(
        .NM     (NM),
        .NS     (NS),
        .S_START(S_START_A),
        .S_END  (S_END_A)
    ) dut (
        .m_bus(wb_m),
        .s_bus(wb_s)
    );

    // =========================================================================
    // Slave — one register
    // =========================================================================
    wb_reg_slave slave0 (.bus(wb_s[0]));

    // =========================================================================
    // Test bookkeeping
    // =========================================================================
    int pass_count = 0;
    int fail_count = 0;

    task automatic check(string name, logic cond);
        if (cond) begin $display("  [PASS] %s", name); pass_count++; end
        else      begin $display("  [FAIL] %s", name); fail_count++; end
    endtask

    // =========================================================================
    // Idle helper (unrolled — no loop-variable interface access)
    // =========================================================================
    task automatic idle_all();
        wb_m[0].adr='0; wb_m[0].mtos='0; wb_m[0].sel=4'hF; wb_m[0].we=0; wb_m[0].cyc=0; wb_m[0].stb=0;
        wb_m[1].adr='0; wb_m[1].mtos='0; wb_m[1].sel=4'hF; wb_m[1].we=0; wb_m[1].cyc=0; wb_m[1].stb=0;
        wb_m[2].adr='0; wb_m[2].mtos='0; wb_m[2].sel=4'hF; wb_m[2].we=0; wb_m[2].cyc=0; wb_m[2].stb=0;
        wb_m[3].adr='0; wb_m[3].mtos='0; wb_m[3].sel=4'hF; wb_m[3].we=0; wb_m[3].cyc=0; wb_m[3].stb=0;
        wb_m[4].adr='0; wb_m[4].mtos='0; wb_m[4].sel=4'hF; wb_m[4].we=0; wb_m[4].cyc=0; wb_m[4].stb=0;
    endtask

    // =========================================================================
    // Master RMW task
    //
    // All interface signals are passed as ref/input so the call sites use
    // constant interface indices (ModelSim constraint), while the repeated
    // protocol logic lives here exactly once.
    // =========================================================================
    task automatic master_rmw (
        // Master-driven outputs (ref: task writes these)
        ref   logic        cyc,
        ref   logic        stb,
        ref   logic        we,
        ref   logic [31:0] adr,
        ref   logic [31:0] mtos,
        ref   logic [ 3:0] sel,
        // Master-received inputs (ref: task must see live signal updates)
        ref   logic        ack,
        ref   logic [31:0] stom,
        // Configuration
        input int          prime,
        input int          iterations
    );
        automatic logic [31:0] rdata;
        sel = 4'hF;
        repeat (iterations) begin
            // READ — assert CYC to grab the crossbar lock
            @(negedge clk);
            cyc=1; adr=REG_ADDR; we=0; stb=1;
            @(posedge clk); #1;
            while (!ack) begin @(posedge clk); #1; end
            rdata = stom;

            // WRITE — CYC remains high, slave stays locked to this master
            @(negedge clk);
            mtos = rdata + prime; we = 1;
            @(posedge clk); #1;
            while (!ack) begin @(posedge clk); #1; end

            // Release
            @(negedge clk); cyc=0; stb=0; we=0;

            // Inter-transaction wait
            repeat (prime) @(posedge clk);
        end
    endtask

    // =========================================================================
    // Main test sequence
    // =========================================================================
    initial begin
        $dumpfile("bus_xbar_atomic_tb.fst");
        $dumpvars(0, bus_xbar_atomic_tb);

        $display("=====================================================");
        $display("  bus_xbar_ctrl: 5-Master Atomic RMW Stress Test   ");
        $display("  N_ITER=%0d  Expected final value: %0d            ", N_ITER, EXPECTED);
        $display("=====================================================");

        // Reset
        idle_all();
        rst = 1;
        repeat (4) @(posedge clk);
        @(negedge clk); rst = 0; #1;

        // -------------------------------------------------------------------
        // Spawn all 5 masters concurrently.
        //
        // Each master keeps CYC high across its read AND write, so the
        // crossbar lock is held for the entire RMW — guaranteeing atomicity.
        //
        // All interface accesses use constant indices (no loop variable)
        // to satisfy ModelSim's interface array elaboration requirement.
        // -------------------------------------------------------------------
        fork
            master_rmw(wb_m[0].cyc, wb_m[0].stb, wb_m[0].we, wb_m[0].adr, wb_m[0].mtos, wb_m[0].sel,
                       wb_m[0].ack, wb_m[0].stom, P0, N_ITER);
            master_rmw(wb_m[1].cyc, wb_m[1].stb, wb_m[1].we, wb_m[1].adr, wb_m[1].mtos, wb_m[1].sel,
                       wb_m[1].ack, wb_m[1].stom, P1, N_ITER);
            master_rmw(wb_m[2].cyc, wb_m[2].stb, wb_m[2].we, wb_m[2].adr, wb_m[2].mtos, wb_m[2].sel,
                       wb_m[2].ack, wb_m[2].stom, P2, N_ITER);
            master_rmw(wb_m[3].cyc, wb_m[3].stb, wb_m[3].we, wb_m[3].adr, wb_m[3].mtos, wb_m[3].sel,
                       wb_m[3].ack, wb_m[3].stom, P3, N_ITER);
            master_rmw(wb_m[4].cyc, wb_m[4].stb, wb_m[4].we, wb_m[4].adr, wb_m[4].mtos, wb_m[4].sel,
                       wb_m[4].ack, wb_m[4].stom, P4, N_ITER);
        join  // wait for all 5 masters to complete their N_ITER iterations

        #5;

        // -------------------------------------------------------------------
        // Verify atomicity: read back the register via the bus (master 0)
        // and also via direct hierarchical access to the slave.
        // If any RMW was non-atomic (two masters read the same old value before
        // either wrote back), the final value would be less than EXPECTED.
        // -------------------------------------------------------------------
        begin
            automatic logic [31:0] readback;

            // Bus readback via master 0
            @(negedge clk);
            wb_m[0].cyc=1; wb_m[0].adr=REG_ADDR; wb_m[0].we=0; wb_m[0].stb=1; wb_m[0].sel=4'hF;
            @(posedge clk); #1;
            while (!wb_m[0].ack) begin @(posedge clk); #1; end
            readback = wb_m[0].stom;
            @(negedge clk); wb_m[0].cyc=0; wb_m[0].stb=0;
            #1;

            check("Atomic RMW: bus readback correct",
                  readback === EXPECTED[31:0]);

            // Direct hierarchical check of slave register
            check("Atomic RMW: slave reg_val correct",
                  slave0.reg_val === EXPECTED[31:0]);
        end

        $display("\n=====================================================");
        $display("  RESULT: %0d PASSED, %0d FAILED", pass_count, fail_count);
        if (fail_count == 0) $display("  ALL TESTS PASSED");
        else                 $display("  SOME TESTS FAILED — atomicity violation?");
        $display("=====================================================");

        $finish;
    end

endmodule
