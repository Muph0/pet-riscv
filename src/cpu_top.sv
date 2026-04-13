module cpu_top (
    input clk27,  // 27 MHz oscillator

    input  pin_rx,
    output pin_tx,

    input pin_step,  // step button (active low)

    output pin_p9,

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
        .clk       (clk27),
        .reset,
        .uart_data,
        .uart_valid,
        .mem_addr  (bl_mem_addr),
        .mem_data  (bl_mem_data),
        .mem_write (bl_mem_write),
        .step      (bl_step),
        .loading   (bl_loading)
    );

    // --- Pipeline interfaces ---
    pc_stage_io pc_io ();
    if_stage_io if_io ();
    id_stage_io id_io ();

    // --- PC stage ---
    assign pc_io.reset       = reset;
    assign pc_io.advance     = bl_step;
    assign pc_io.pc_redirect = '0;
    assign pc_io.pc_target   = '0;

    pc_stage pcs (
        .clk(clk27),
        .io (pc_io.in)
    );

    // --- IF stage ---
    assign if_io.reset    = reset;
    assign if_io.stall    = !bl_step;
    assign if_io.loading  = bl_loading;
    assign if_io.bl_addr  = bl_mem_addr;
    assign if_io.bl_data  = bl_mem_data;
    assign if_io.bl_write = bl_mem_write;

    if_stage ifs (
        .clk (clk27),
        .io  (if_io.in),
        .prev(pc_io.prev)
    );

    // --- ID stage ---
    assign id_io.reset = reset;
    assign id_io.stall = !bl_step;

    id_stage ids (
        .clk (clk27),
        .io  (id_io.in),
        .prev(if_io.prev)
    );

    // --- Status LEDs ---
    assign led5   = !bl_loading;   // lit when done loading
    assign led4   = bl_step;          // blinks when stepping
    assign pin_p9 = !bl_loading;

    // --- Reset ---
    always_ff @(posedge clk27) begin
        reset <= '0;
    end

endmodule
