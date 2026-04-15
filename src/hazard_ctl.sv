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

    // Default: pass through reset and advance to all stages
    always_comb begin
        sPC.reset   = reset;
        sPC.advance = !halt;
        sIF.reset   = reset;
        sIF.enable  = !halt;
        sID.reset   = reset;
        sID.enable  = !halt;
        sEX.reset   = reset;
        sEX.enable  = !halt;
        sMEM.reset  = reset;
        sMEM.enable = !halt;
    end

endmodule
