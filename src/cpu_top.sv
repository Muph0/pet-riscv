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

    // --- Pipeline interfaces ---
    pc_stage_io pc_io ();
    if_stage_io if_io ();
    id_stage_io id_io ();

    // --- PC stage ---
    assign pc_io.reset       = reset;
    assign pc_io.enable      = !if_io.loading;
    assign pc_io.step        = !pin_step;  // active-low button
    assign pc_io.run         = '0;  // step mode only for now
    assign pc_io.pc_redirect = '0;
    assign pc_io.pc_target   = '0;

    pc_stage pcs (
        .clk(clk27),
        .io (pc_io.in)
    );

    // --- IF stage ---
    assign if_io.reset      = reset;
    assign if_io.stall      = pc_io.halted;
    assign if_io.uart_data  = uart_data;
    assign if_io.uart_valid = uart_valid;

    if_stage ifs (
        .clk (clk27),
        .io  (if_io.in),
        .prev(pc_io.prev)
    );

    // --- ID stage ---
    assign id_io.reset = reset;
    assign id_io.stall = pc_io.halted;

    id_stage ids (
        .clk (clk27),
        .io  (id_io.in),
        .prev(if_io.prev)
    );

    // --- Status LEDs ---
    assign led5   = !if_io.loading;  // lit when done loading
    assign led4   = !pc_io.halted;  // lit when running
    assign pin_p9 = !if_io.loading;

    // --- Reset ---
    always_ff @(posedge clk27) begin
        reset <= '0;
    end

endmodule
