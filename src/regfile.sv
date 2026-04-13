module regfile (
    // Control signals
    input clk,
    input write,

    // Write port
    input [ 4:0] dest,
    input [31:0] dest_data,

    // Read ports
    input  logic [ 4:0] src1,
    input  logic [ 4:0] src2,
    output logic [31:0] src1_data,
    output logic [31:0] src2_data
);

    logic [31:0] data[31:1];

    // Async read
    always_comb begin
        src1_data = src1 == 5'd0 ? '0 : (write && src1 == dest) ? dest_data : data[src1];
        src2_data = src2 == 5'd0 ? '0 : (write && src2 == dest) ? dest_data : data[src2];
    end

    // Sync write
    always_ff @(posedge clk) begin
        if (write && dest != 5'd0) data[dest] <= dest_data;
    end

endmodule  //regfile
