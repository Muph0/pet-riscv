module interrupt_ctl (
    input clk,
    input [31:0] pending,

    stagePC_face.intctl pc,
    CSR.intctl csr
);

endmodule
