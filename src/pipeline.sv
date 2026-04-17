module pipeline #(
    parameter logic [31:0] PC_RESET = 32'h0000_1000
) (
    input logic clk,
    input logic reset,
    input logic halt,

    // Wishbone master interfaces (directly connected to crossbar)
    wishbone.master ibus,  // instruction fetch
    wishbone.master dbus   // data load/store
);

    // --- Pipeline interfaces ---
    stagePC_face pc_io ();
    stageIF_face if_io ();
    stageID_face id_io ();
    stageEX_face ex_io ();
    stageMEM_face mem_io ();
    stageWB_face wb_io ();

    // --- PC stage ---
    assign pc_io.pc_redirect = ex_io.branch_taken;
    assign pc_io.pc_target   = ex_io.branch_target[31:2];

    stagePC #(
        .PC_RESET(PC_RESET)
    ) sPC (
        .clk,
        .io(pc_io.in)
    );

    // --- IF stage ---
    stageIF sIF (
        .clk,
        .io  (if_io.in),
        .prev(pc_io.prev),
        .ibus(ibus)
    );

    // --- ID stage ---
    assign id_io.fw_data_ex  = ex_io.alu_result_comb;  // combinational ALU (in EX now)
    assign id_io.fw_data_mem = ex_io.alu_result;  // registered EX (in MEM now)
    assign id_io.fw_data_wb  = wb_io.rd_data;  // WB output (handles loads too)

    stageID sID (
        .clk,
        .io  (id_io.in),
        .prev(if_io.prev),
        .wb  (wb_io.id)
    );

    // --- EX stage ---
    stageEX sEX (
        .clk,
        .io (ex_io.in),
        .sID(id_io.prev)
    );

    // --- MEM stage ---
    stageMEM sMEM (
        .clk,
        .io  (mem_io.in),
        .prev(ex_io.prev),
        .dbus(dbus)
    );

    // --- WB stage ---
    stageWB sWB (
        .clk,
        .io  (wb_io.in),
        .prev(mem_io.prev)
    );

    // --- Hazard control ---
    hazard_ctl hazard (
        .clk,
        .reset,
        .halt,
        .sPC (pc_io.hazard),
        .sIF (if_io.hazard),
        .sID (id_io.hazard),
        .sEX (ex_io.hazard),
        .sMEM(mem_io.hazard),
        .sWB (wb_io.hazard)
    );

endmodule
