interface wishbone #(
    parameter ADDR_WIDTH = 32,
    parameter DATA_WIDTH = 32
) (
    input logic clk,
    input logic reset
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
    logic                  rty;  // Retry: Indicates Slave is busy (in use by another master)

    // Port for the Master (CPU, DMA, etc.)
    modport master(output adr, mtos, sel, we, cyc, stb, input stom, ack, err, rty, clk, reset);

    // Port for the Slave (Memory, UART, etc.)
    modport slave(input adr, mtos, sel, we, cyc, stb, clk, reset, output stom, ack, err, rty);

endinterface

// Crossbar controller/arbiter for the Wishbone bus
// ------------------------------------------------
// This module implements a fully‑connected *star‑topology* Wishbone crossbar,
// allowing NM masters to access NS slaves concurrently, provided they target
// different slaves. Each slave has an independent arbitration domain.
//
// Key Features:
// - **Address‑based routing:** Each slave is assigned a static, non‑overlapping
//   address range via S_START[] / S_END[]. Masters are dynamically routed to
//   the slave whose range matches the current address.
// - **Per‑slave arbitration:** Each slave has its own arbiter. If multiple
//   masters request the same slave, the arbiter grants access using a fixed
//   priority scheme (lower‑index masters win). Other masters receive RTY until
//   the slave becomes free.
// - **Slave locking:** Once a master wins arbitration for a slave, that slave
//   remains *locked* to the master until the master deasserts CYC. This ensures
//   atomic multi‑cycle Wishbone transactions and prevents mid‑cycle preemption.
// - **Parallelism:** Masters accessing *different* slaves proceed fully in
//   parallel with no interference. Only masters contending for the same slave
//   are serialized.
// - **Return‑path demultiplexing:** Responses (ACK/ERR/RTY/data) from each slave
//   are routed back only to the currently owning master. Non‑owners receive RTY
//   if they attempt to access a busy slave.
// - **Address error detection:** If a master asserts STB/CYC but its address
//   does not match any slave range, the controller returns ERR.
// - **Simulation‑time validation:** The initial block checks for invalid or
//   overlapping address ranges and reports configuration errors early.
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
            // 1. Check for valid start/end range (END inclusive: START <= END)
            if (S_START[i] > S_END[i]) begin
                $error("XBAR CONFIG ERROR: Slave %0d has invalid range [0x%0h : 0x%0h]", i,
                       S_START[i], S_END[i]);
            end

            // 2. Check for overlapping ranges with other slaves
            for (int j = i + 1; j < NS; j++) begin
                if ((S_START[i] <= S_END[j]) && (S_START[j] <= S_END[i])) begin
                    $error(
                        "XBAR CONFIG ERROR: Overlap between Slave %0d [0x%0h : 0x%0h] and Slave %0d [0x%0h : 0x%0h]",
                        i, S_START[i], S_END[i], j, S_START[j], S_END[j]);
                end
            end
        end
    end
    // synthesis translate_on

    // Using clock and reset from the first master interface
    // (Assuming synchronous bus where all interfaces share clk/reset)
    logic clk, reset;
    assign clk   = m_bus[0].clk;
    assign reset = m_bus[0].reset;

    // ==============================================================================
    // FLAT SIGNAL ARRAYS
    // ModelSim (2020) does not support non-constant indices into interface arrays.
    // All interface members are mirrored into plain logic arrays so the routing
    // logic can freely use variable indices. A generate block with a constant
    // genvar connects the two sides at the port boundaries.
    // ==============================================================================

    // Master inputs (driven by the master side / testbench)
    logic [31:0] m_adr_f [NM];
    logic [31:0] m_mtos_f[NM];
    logic [ 3:0] m_sel_f [NM];
    logic        m_we_f  [NM];
    logic        m_cyc_f [NM];
    logic        m_stb_f [NM];

    // Master outputs (driven by this module, returned to master)
    logic [31:0] m_stom_d[NM];
    logic        m_ack_d [NM];
    logic        m_err_d [NM];
    logic        m_rty_d [NM];

    // Slave outputs (driven by this module, forwarded to slave)
    logic [31:0] s_adr_d [NS];
    logic [31:0] s_mtos_d[NS];
    logic [ 3:0] s_sel_d [NS];
    logic        s_we_d  [NS];
    logic        s_cyc_d [NS];
    logic        s_stb_d [NS];

    // Slave inputs (driven by the slave side)
    logic [31:0] s_stom_f[NS];
    logic        s_ack_f [NS];
    logic        s_err_f [NS];
    logic        s_rty_f [NS];

    genvar gi;
    generate
        for (gi = 0; gi < NM; gi++) begin : gen_m_flat
            // Master → flat
            assign m_adr_f[gi] = m_bus[gi].adr;
            assign m_mtos_f[gi] = m_bus[gi].mtos;
            assign m_sel_f[gi] = m_bus[gi].sel;
            assign m_we_f[gi] = m_bus[gi].we;
            assign m_cyc_f[gi] = m_bus[gi].cyc;
            assign m_stb_f[gi] = m_bus[gi].stb;
            // Flat → master interface outputs
            assign m_bus[gi].stom = m_stom_d[gi];
            assign m_bus[gi].ack = m_ack_d[gi];
            assign m_bus[gi].err = m_err_d[gi];
            assign m_bus[gi].rty = m_rty_d[gi];
        end

        for (gi = 0; gi < NS; gi++) begin : gen_s_flat
            // Slave → flat
            assign s_stom_f[gi] = s_bus[gi].stom;
            assign s_ack_f[gi] = s_bus[gi].ack;
            assign s_err_f[gi] = s_bus[gi].err;
            assign s_rty_f[gi] = s_bus[gi].rty;
            // Flat → slave interface outputs
            assign s_bus[gi].adr = s_adr_d[gi];
            assign s_bus[gi].mtos = s_mtos_d[gi];
            assign s_bus[gi].sel = s_sel_d[gi];
            assign s_bus[gi].we = s_we_d[gi];
            assign s_bus[gi].cyc = s_cyc_d[gi];
            assign s_bus[gi].stb = s_stb_d[gi];
        end
    endgenerate

    // ==============================================================================
    // CROSSBAR ROUTING & ARBITRATION LOGIC
    // ==============================================================================

    logic [NS-1:0] m_req  [NM];
    logic          matched[NM];
    int            target [NM];

    // Stateful Arbitration Registers
    logic          s_busy [NS];  // Is the slave currently locked?
    int            s_owner[NS];  // Which master currently owns the slave?

    // 1. Address Decoding (Combinatorial)
    always_comb begin
        for (int m = 0; m < NM; m++) begin
            matched[m] = 1'b0;
            target[m]  = 0;
            for (int s = 0; s < NS; s++) begin
                m_req[m][s] = 1'b0;
                // Master requests slave if CYC is high and address matches
                if (m_cyc_f[m] && (m_adr_f[m] >= S_START[s] && m_adr_f[m] <= S_END[s])) begin
                    m_req[m][s] = 1'b1;
                    matched[m]  = 1'b1;
                    target[m]   = s;
                end
            end
        end
    end

    // 2. Stateful Arbitration (Sequential)
    always_ff @(posedge clk) begin
        if (reset) begin
            for (int s = 0; s < NS; s++) begin
                s_busy[s]  <= 1'b0;
                s_owner[s] <= 0;
            end
        end else begin
            for (int s = 0; s < NS; s++) begin
                if (s_busy[s]) begin
                    // SLAVE IS LOCKED: Wait for the owning master to drop CYC
                    if (!m_cyc_f[s_owner[s]]) begin
                        s_busy[s] <= 1'b0;  // Release lock
                    end
                end else begin
                    // SLAVE IS IDLE: Arbitrate new requests
                    // Loop starts from 0 to prioritize lower-indexed masters
                    for (int m = 0; m < NM; m++) begin
                        if (m_req[m][s]) begin
                            s_busy[s]  <= 1'b1;
                            s_owner[s] <= m;
                            break;  // Highest priority master found, lock and stop looking
                        end
                    end
                end
            end
        end
    end

    // 3. MUX Master -> Slave (Forward Path)
    always_comb begin
        for (int s = 0; s < NS; s++) begin
            if (s_busy[s]) begin
                s_adr_d[s]  = m_adr_f[s_owner[s]];
                s_mtos_d[s] = m_mtos_f[s_owner[s]];
                s_sel_d[s]  = m_sel_f[s_owner[s]];
                s_we_d[s]   = m_we_f[s_owner[s]];
                s_cyc_d[s]  = m_cyc_f[s_owner[s]];
                s_stb_d[s]  = m_stb_f[s_owner[s]];
            end else begin
                s_adr_d[s]  = '0;
                s_mtos_d[s] = '0;
                s_sel_d[s]  = '0;
                s_we_d[s]   = 1'b0;
                s_cyc_d[s]  = 1'b0;
                s_stb_d[s]  = 1'b0;
            end
        end
    end

    // 4. MUX Slave -> Master (Return Path)
    always_comb begin
        for (int m = 0; m < NM; m++) begin
            m_stom_d[m] = '0;
            m_ack_d[m]  = 1'b0;
            m_err_d[m]  = 1'b0;
            m_rty_d[m]  = 1'b0;

            if (m_cyc_f[m]) begin
                if (matched[m]) begin
                    // Check if this master currently owns the target slave
                    if (s_busy[target[m]] && (s_owner[target[m]] == m)) begin
                        // Connection is active and granted to this master
                        m_stom_d[m] = s_stom_f[target[m]];
                        m_ack_d[m]  = s_ack_f[target[m]];
                        m_err_d[m]  = s_err_f[target[m]];
                        m_rty_d[m]  = s_rty_f[target[m]];
                    end else begin
                        // Target slave is busy with a different master, or arbitration is pending
                        // Issue a retry so the master backs off and tries again
                        m_rty_d[m] = 1'b1;
                    end
                end else if (m_stb_f[m]) begin
                    // Address does not map to any known slave
                    m_err_d[m] = 1'b1;
                end
            end
        end
    end

endmodule
