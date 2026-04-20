module cpu_top (
    input logic clk27,  // 27 MHz oscillator

    input  logic pin_rx,
    output logic pin_tx,

    output logic led4,
    output logic led5
);

    // =========================================================================
    // Internal reset — deasserts one cycle after power-on
    // =========================================================================
    logic reset = 1'b1;
    always_ff @(posedge clk27) reset <= 1'b0;

    // =========================================================================
    // Bootloader path — standalone uart_rx → bootloader FSM → pipeline BSRAM
    //
    // This path is independent of the Wishbone bus: the bootloader loads
    // programs without any CPU involvement, so it works before the CPU runs.
    // =========================================================================
    logic [7:0] uart_data;
    logic       uart_valid;

    uart_rx rx_bl (
        .clk       (clk27),
        .reset     (reset),
        .rx0       (pin_rx),
        .bit_len   (16'(27_000_000 / 115_200)),
        .data_out  (uart_data),
        .data_valid(uart_valid)
    );

    logic [31:0] bl_mem_addr;
    logic [ 7:0] bl_mem_data;
    logic        bl_mem_write;
    logic        bl_run;
    logic        bl_loading;

    bootloader bl (
        .clk       (clk27),
        .reset     (reset),
        .uart_data (uart_data),
        .uart_valid(uart_valid),
        .mem_addr  (bl_mem_addr),
        .mem_data  (bl_mem_data),
        .mem_write (bl_mem_write),
        .run       (bl_run),
        .loading   (bl_loading)
    );

    // =========================================================================
    // Wishbone crossbar
    // =========================================================================
    localparam logic [31:0] ROM__ADR = 32'h0000_4000;
    localparam logic [31:0] ROM__END = 32'h0000_5FFF;
    localparam logic [31:0] SRAM_ADR = 32'h0000_8000;
    localparam logic [31:0] SRAM_END = 32'h0000_9FFF;
    localparam logic [31:0] UART_ADR = 32'h1000_0000;
    localparam logic [31:0] UART_END = 32'h1000_000F;
    localparam logic [31:0] DDR__ADR = 32'h8000_0000;
    localparam logic [31:0] DDR__END = 32'hFFFF_FFFF;

    // --- Named master interfaces ---
    wishbone ibus (
        .clk  (clk27),
        .reset(reset)
    );  // M0: instruction fetch (idle)
    wishbone dbus (
        .clk  (clk27),
        .reset(reset)
    );  // M1: load/store        (idle)

    // --- Named slave interfaces ---
    wishbone uart_bus (
        .clk  (clk27),
        .reset(reset)
    );  // S0: UART MMIO
    wishbone ddr_bus (
        .clk  (clk27),
        .reset(reset)
    );  // S1: ext. DDR DRAM (null stub until DDR PHY added)
    wishbone bsram_bus (
        .clk  (clk27),
        .reset(reset)
    );  // S2: on-chip BSRAM     (idle stub)
    wishbone rom_bus (
        .clk  (clk27),
        .reset(reset)
    );  // S3: boot ROM          (idle stub)

    // Keep DDR slave stub quiet (replace with DDR PHY when ready)
    assign ddr_bus.stom = '0;
    assign ddr_bus.ack  = '0;
    assign ddr_bus.err  = '0;
    assign ddr_bus.rty  = '0;

    bus_xbar_ctrl #(
        .NM     (2),
        .NS     (4),
        .S_START('{UART_ADR, DDR__ADR, SRAM_ADR, ROM__ADR}),
        .S_END  ('{UART_END, DDR__END, SRAM_END, ROM__END})
    ) xbar (
        .m_bus('{ibus, dbus}),
        .s_bus('{uart_bus, ddr_bus, bsram_bus, rom_bus})
    );

    // --- Slave 0: UART Wishbone wrapper ---
    // Gate RX to idle (1) while bootloader is running so the periph
    // does not capture bootloader traffic as application data.
    uart_wb #(
        .BASE_ADDR(UART_ADR),
        .END_ADDR (UART_END)
    ) u_uart (
        .rx_pin(bl_run ? pin_rx : 1'b1),
        .tx_pin(pin_tx),
        .bus   (uart_bus)
    );
    // --- Slaves 2 & 3: Dual-port BSRAM (port A = IROM, port B = SRAM) ---
    wb_dp_4Kx32b u_dpram (
        .bus_a   (rom_bus),
        .bus_b   (bsram_bus),
        .bl_addr (bl_mem_addr),
        .bl_data (bl_mem_data),
        .bl_write(bl_mem_write)
    );

    // =========================================================================
    // Pipeline — CPU core (connects to ibus / dbus masters)
    // =========================================================================
    pipeline #(
        .PC_RESET(ROM__ADR)
    ) pipe (
        .clk  (clk27),
        .reset(reset),
        .halt (!bl_run),
        .ibus (ibus),
        .dbus (dbus)
    );

    // =========================================================================
    // Status LEDs
    // =========================================================================
    assign led5 = !bl_loading;  // lit when done loading
    assign led4 = bl_run;  // lit when CPU is running

endmodule
