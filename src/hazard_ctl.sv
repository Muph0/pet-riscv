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

    // Default: pass through reset and advance to all stages
    always_comb begin
        sPC.reset   = reset;
        sPC.advance = !halt && !load_stall;
        sIF.reset   = reset || flush;
        sIF.enable  = !halt && !load_stall;
        sID.reset   = reset || flush || (!halt && load_stall);  // bubble on stall or flush
        sID.enable  = !halt && !load_stall;
        sEX.reset   = reset;
        sEX.enable  = !halt;
        sMEM.reset  = reset;
        sMEM.enable = !halt;
    end

endmodule
