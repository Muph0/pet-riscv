module businfo_wb #(
    parameter logic [31:0] BASE_ADDR = 32'h1000_0000,
    parameter logic [31:0] END_ADDR  = 32'h1000_002F
) (
    input logic [1:0] ddr_status,
    wishbone.slave bus
);

    logic clk;
    logic reset;
    assign clk   = bus.clk;
    assign reset = bus.reset;

    logic [31:0] read_data;

    always_ff @(posedge clk) begin
        if (reset) begin
            bus.ack  <= 1'b0;
            bus.err  <= 1'b0;
            bus.rty  <= 1'b0;
            bus.stom <= 32'b0;
        end else begin
            bus.ack <= 1'b0;
            bus.err <= 1'b0;

            if (bus.stb && bus.cyc && !bus.ack) begin
                bus.ack <= 1'b1;
                if (bus.we) begin
                    bus.err <= 1'b1;
                end else begin
                    case (bus.adr - BASE_ADDR)
                        8'h00: bus.stom <= 32'h6F666E49;  // "Info" 49 6E 66 6F
                        8'h04: bus.stom <= 32'h10000000;  // Start
                        8'h08: bus.stom <= 32'h1000002F;  // End
                        8'h0C: bus.stom <= 32'h00000000;  // Status

                        8'h10: bus.stom <= 32'h54524155;  // "UART"
                        8'h14: bus.stom <= 32'h10010000;  // Start
                        8'h18: bus.stom <= 32'h1001000F;  // End
                        8'h1C: bus.stom <= 32'h00000000;  // Status

                        8'h20: bus.stom <= 32'h33524444;  // "DDR3"
                        8'h24: bus.stom <= 32'h80000000;  // Start
                        8'h28: bus.stom <= 32'h87FFFFFF;  // End
                        8'h2C: bus.stom <= {30'b0, ddr_status};  // Status

                        default: bus.stom <= 32'h0;
                    endcase
                end
            end
        end
    end

endmodule
