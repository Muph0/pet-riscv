module hazard_ctl (
    input clk,
    input reset,
    input halt,

    stagePC_face.hazard  sPC,
    stageIF_face.hazard  sIF,
    stageID_face.hazard  sID,
    stageEX_face.hazard  sEX,
    stageMEM_face.hazard sMEM,
    stageWB_face.hazard  sWB
);
    import mem_pkg::*;

    // --- Load detection ---
    wire ex_is_load = (sID.mem_mode == MEM_LOAD_SIG || sID.mem_mode == MEM_LOAD_USIG);
    wire mem_is_load = (sEX.mem_mode == MEM_LOAD_SIG || sEX.mem_mode == MEM_LOAD_USIG);

    // --- Forwarding logic ---
    // sID.rd/wb_en  = instruction now in EX  (1 stage ahead)
    // sEX.rd/wb_en  = instruction now in MEM (2 stages ahead)
    // sMEM.rd/wb_en = instruction now in WB  (3 stages ahead)
    // Priority: EX > MEM > WB > regfile

    wire ex_wr = sID.wb_en && (sID.rd != 5'd0) && !ex_is_load;
    wire mem_wr = sEX.wb_en && (sEX.rd != 5'd0) && !mem_is_load;
    wire wb_wr = sMEM.wb_en && (sMEM.rd != 5'd0);

    // --- Load-use hazard detection ---
    // A load in EX (sID) or MEM (sEX) whose rd matches a source
    // of the instruction being decoded requires a stall.
    wire load_use_ex  = ex_is_load  && sID.wb_en && (sID.rd != 5'd0) &&
                        (sID.rd == sID.rs1_next || sID.rd == sID.rs2_next);
    wire load_use_mem = mem_is_load && sEX.wb_en && (sEX.rd != 5'd0) &&
                        (sEX.rd == sID.rs1_next || sEX.rd == sID.rs2_next);

    wire load_stall = load_use_ex || load_use_mem;

    always_comb begin
        // rs1 forwarding
        if (ex_wr && sID.rd == sID.rs1_next) sID.fw_sel1 = 2'b01;
        else if (mem_wr && sEX.rd == sID.rs1_next) sID.fw_sel1 = 2'b10;
        else if (wb_wr && sMEM.rd == sID.rs1_next) sID.fw_sel1 = 2'b11;
        else sID.fw_sel1 = 2'b00;

        // rs2 forwarding
        if (ex_wr && sID.rd == sID.rs2_next) sID.fw_sel2 = 2'b01;
        else if (mem_wr && sEX.rd == sID.rs2_next) sID.fw_sel2 = 2'b10;
        else if (wb_wr && sMEM.rd == sID.rs2_next) sID.fw_sel2 = 2'b11;
        else sID.fw_sel2 = 2'b00;
    end

    // --- Branch flush ---
    // When a branch is taken in EX, flush the two instructions
    // that entered IF and ID after the branch.
    wire flush = sEX.branch_taken;

    // ---- Stall domains ----
    // back_freeze : halt or MEM bus wait → freeze entire pipeline
    // front_freeze: IF bus wait or load-use → freeze PC/IF, bubble ID,
    //               let EX/MEM/WB drain
    wire if_stall = sIF.wb_stall;
    wire mem_stall = sMEM.wb_stall;

    wire back_freeze = halt || mem_stall;
    wire front_freeze = if_stall || load_stall;

    always_comb begin
        // PC: stall unless flush (branch redirect must update PC even during
        //     a back-end stall so the target is not lost).
        sPC.reset  = reset;
        sPC.stall  = (back_freeze || front_freeze) && !flush;

        // IF: freeze on any stall.  Reset during halt/flush keeps the
        //     fetch state machine in S_FETCH with the bus gated off.
        sIF.reset  = reset || flush || halt;
        sIF.stall  = back_freeze || front_freeze;

        // ID: freeze on back stall; bubble on front stall or flush.
        sID.reset  = reset || flush || (!back_freeze && front_freeze);
        sID.stall  = back_freeze || front_freeze;

        // EX / MEM: freeze on back stall only.
        sEX.reset  = reset;
        sEX.stall  = back_freeze;
        sMEM.reset = reset;
        sMEM.stall = back_freeze;
    end

endmodule
