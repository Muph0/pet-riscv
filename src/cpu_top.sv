module cpu_top (
    input clk27,  // 27 MHz oscillator

    input  pin_rx,
    output pin_tx,

    input btn_step,  // step button (active low)

    output led4,
    output led5
);

    logic reset = '1;

    assign pin_tx = pin_rx;

    // --- UART RX ---
    logic [7:0] uart_data;
    logic       uart_valid;

    uart_rx rx1 (
        .clk(clk27),
        .reset,
        .rx0(pin_rx),
        .data_out(uart_data),
        .data_valid(uart_valid)
    );

    // --- Bootloader ---
    logic [31:0] bl_mem_addr;
    logic [ 7:0] bl_mem_data;
    logic        bl_mem_write;
    logic        bl_step;
    logic        bl_loading;

    bootloader bl (
        .clk      (clk27),
        .reset,
        .uart_data,
        .uart_valid,
        .mem_addr (bl_mem_addr),
        .mem_data (bl_mem_data),
        .mem_write(bl_mem_write),
        .step     (bl_step),
        .loading  (bl_loading)
    );

    // --- Pipeline ---
    pipeline pipe (
        .clk     (clk27),
        .reset,
        .halt    (!bl_step),
        .loading (bl_loading),
        .bl_addr (bl_mem_addr),
        .bl_data (bl_mem_data),
        .bl_write(bl_mem_write)
    );

    // --- Status LEDs ---
    assign led5 = !bl_loading;  // lit when done loading
    assign led4 = bl_step;  // blinks when stepping

    // --- Reset ---
    always_ff @(posedge clk27) begin
        reset <= '0;
    end

endmodule
