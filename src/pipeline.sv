module pipeline (
    input logic clk,
    input logic reset,
    input logic halt,

    // Bootloader memory port
    input logic        loading,
    input logic [31:0] bl_addr,
    input logic [ 7:0] bl_data,
    input logic        bl_write
);

    // --- Pipeline interfaces ---
    stagePC_face pc_io ();
    stageIF_face if_io ();
    stageID_face id_io ();
    stageEX_face ex_io ();
    stageMEM_face mem_io ();
    stageWB_face wb_io ();

    // --- PC stage ---
    assign pc_io.pc_redirect = '0;
    assign pc_io.pc_target   = '0;

    stagePC sPC (
        .clk,
        .io(pc_io.in)
    );

    // --- IF stage ---
    assign if_io.loading  = loading;
    assign if_io.bl_addr  = bl_addr;
    assign if_io.bl_data  = bl_data;
    assign if_io.bl_write = bl_write;

    stageIF sIF (
        .clk,
        .io  (if_io.in),
        .prev(pc_io.prev)
    );

    // --- ID stage ---
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
        .prev(ex_io.prev)
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
