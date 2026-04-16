module uart_wb #(
    parameter logic [31:0] BASE_ADDR = 32'h1000_0000,
    parameter logic [31:0] END_ADDR  = 32'h1000_0010
) (
    input rx_pin,
    output tx_pin,
    wishbone.slave bus
);

    wire clk = bus.clk;
    wire reset = bus.reset;

    wire [7:0] rx_byte;
    wire rx_valid;
    uart_rx rx (
        .clk,
        .reset,
        .rx0(rx_pin),
        .bit_len,
        .data_out(rx_byte),
        .data_valid(rx_valid)
    );

    // MMIO registers:

    // address +0
    logic [ 7:0] tx_data;  // <- write, writing sets the TX full bit
    logic [ 7:0] rx_data;  // -> read, reading clears the RX full bit

    // address +1
    logic [ 1:0] status;  // -> read, bits: 0: TX full, 1: RX full

    // address +2
    logic [ 2:0] control;  // r/w, bits: 0: TX enable, 1: RX enable, 2: IRQ enable

    // address +4
    logic [15:0] bit_len;  // r/w, bit length in clock ticks, aka "clock divider"

    // address +16 END

    always_ff @(posedge clk) begin
        if (reset) begin
            status  <= '0;
            tx_data <= '0;
            rx_data <= '0;
            control <= '0;
            bit_len <= (27_000_000 / 115200);
        end else begin
            status <= {1'b0, status[0] | rx_valid};
        end
        // TODO: wishbone slave here
    end

endmodule


