interface wishbone #(
    parameter ADDR_WIDTH = 32,
    parameter DATA_WIDTH = 32
) (
    input logic clk,
    input logic rst
);

    // --- Master to Slave Signals ---
    logic [ADDR_WIDTH-1:0] adr;  // Address of the transfer
    logic [DATA_WIDTH-1:0] mtos;  // Data sent from Master to Slave
    logic [           3:0] sel;  // Byte Select (e.g., 4'b0001 = first byte only)
    logic                  we;  // Write Enable (1 = Write, 0 = Read)
    logic                  cyc;  // Cycle: held 1 during the whole transaction
    logic                  stb;  // Strobe: 1 = tell slave that adr is valid

    // --- Slave to Master Signals ---
    logic [DATA_WIDTH-1:0] stom;  // Data sent from Slave to Master
    logic                  ack;  // Acknowledge: 1 = tell master stom is valid
    logic                  err;  // Error: Indicates invalid address (no slave on that address)
    logic                  busy;  // Indicates Slave is busy (in use by other master now)

    // Port for the Master (CPU, DMA, etc.)
    modport master(output adr, mtos, sel, we, cyc, stb, input stom, ack, err, busy, clk, rst);

    // Port for the Slave (Memory, UART, etc.)
    modport slave(input adr, mtos, sel, we, cyc, stb, clk, rst, output stom, ack, err, busy);

endinterface

module bus_xbar_ctrl #(
    parameter int NM = 2,  // Number of Masters
    parameter int NS = 3,  // Number of Slaves
    // Address ranges: Slave 0: [0x0, 0x1000), etc.
    parameter logic [31:0] S_START[NS] = '{32'h0000_0000, 32'h1000_0000, 32'h2000_0000},
    parameter logic [31:0] S_END[NS] = '{32'h1000_0000, 32'h1000_0100, 32'h3000_0000}
) (
    wishbone.slave  m_bus[NM],
    wishbone.master s_bus[NS]
);

    // SIMULATION ONLY: Address Overlap and Validity Check
    // synthesis translate_off
    initial begin
        for (int i = 0; i < NS; i++) begin
            // 1. Check for valid start/end range
            if (S_START[i] >= S_END[i]) begin
                $error("XBAR CONFIG ERROR: Slave %0d has invalid range [0x%0h : 0x%0h]", i,
                       S_START[i], S_END[i]);
            end

            // 2. Check for overlapping ranges with other slaves
            for (int j = i + 1; j < NS; j++) begin
                if ((S_START[i] < S_END[j]) && (S_START[j] < S_END[i])) begin
                    $error(
                        "XBAR CONFIG ERROR: Overlap between Slave %0d [0x%0h : 0x%0h] and Slave %0d [0x%0h : 0x%0h]",
                        i, S_START[i], S_END[i], j, S_START[j], S_END[j]);
                end
            end
        end
    end
    // synthesis translate_on

    // ==============================================================================
    // CROSSBAR ROUTING & ARBITRATION LOGIC
    // ==============================================================================

    logic [NS-1:0] m_req  [NM];  // m_req[m][s]: Master 'm' is requesting Slave 's'
    int            grant  [NS];  // grant[s]: Which Master won access to Slave 's'
    logic          active [NS];  // active[s]: Is Slave 's' currently targeted?
    logic          matched[NM];  // matched[m]: Did Master 'm' address a valid Slave?
    int            target [NM];  // target[m]: The valid Slave index targeted by Master 'm'

    always_comb begin
        // 1. Initialize variables to defaults to prevent inferred latches
        for (int m = 0; m < NM; m++) begin
            matched[m] = 1'b0;
            target[m]  = 0;
            for (int s = 0; s < NS; s++) begin
                m_req[m][s] = 1'b0;
            end
        end

        for (int s = 0; s < NS; s++) begin
            grant[s]  = 0;
            active[s] = 1'b0;
        end

        // 2. Address Decoding: Determine which master wants which slave
        for (int m = 0; m < NM; m++) begin
            if (m_bus[m].cyc) begin
                for (int s = 0; s < NS; s++) begin
                    if (m_bus[m].adr >= S_START[s] && m_bus[m].adr < S_END[s]) begin
                        m_req[m][s] = 1'b1;
                        matched[m]  = 1'b1;
                        target[m]   = s;
                    end
                end
            end
        end

        // 3. Arbitration: Decide which master gets access to a contested slave
        // Fixed Priority scheme: Lower master index (m=0) has higher priority.
        // Reversing the loop ensures the lower index overrides higher index assignments.
        for (int s = 0; s < NS; s++) begin
            for (int m = NM - 1; m >= 0; m--) begin
                if (m_req[m][s]) begin
                    active[s] = 1'b1;
                    grant[s]  = m;
                end
            end
        end

        // 4. MUX Master -> Slave (Forward Path)
        for (int s = 0; s < NS; s++) begin
            if (active[s]) begin
                s_bus[s].adr  = m_bus[grant[s]].adr;
                s_bus[s].mtos = m_bus[grant[s]].mtos;
                s_bus[s].sel  = m_bus[grant[s]].sel;
                s_bus[s].we   = m_bus[grant[s]].we;
                s_bus[s].cyc  = m_bus[grant[s]].cyc;
                s_bus[s].stb  = m_bus[grant[s]].stb;
            end else begin
                // Tie off unused slave ports cleanly
                s_bus[s].adr  = '0;
                s_bus[s].mtos = '0;
                s_bus[s].sel  = '0;
                s_bus[s].we   = 1'b0;
                s_bus[s].cyc  = 1'b0;
                s_bus[s].stb  = 1'b0;
            end
        end

        // 5. MUX Slave -> Master (Return Path)
        for (int m = 0; m < NM; m++) begin
            // Default inactive state
            m_bus[m].stom = '0;
            m_bus[m].ack  = 1'b0;
            m_bus[m].err  = 1'b0;
            m_bus[m].busy = 1'b0;

            if (m_bus[m].cyc) begin
                if (matched[m]) begin
                    if (active[target[m]] && (grant[target[m]] == m)) begin
                        // Master successfully established connection
                        m_bus[m].stom = s_bus[target[m]].stom;
                        m_bus[m].ack  = s_bus[target[m]].ack;
                        m_bus[m].err  = s_bus[target[m]].err;
                        m_bus[m].busy = s_bus[target[m]].busy;
                    end else begin
                        // Target slave is busy with a higher priority master
                        m_bus[m].busy = 1'b1;
                    end
                end else begin
                    // Address does not map to any known slave
                    if (m_bus[m].stb) begin
                        m_bus[m].err = 1'b1;
                    end
                end
            end
        end
    end

endmodule
