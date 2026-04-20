module cpu_top (
    input logic clk27,  // 27 MHz oscillator
    input logic key2,   // Silicone Key 2 (active low) — resets bootloader

    input  logic pin_rx,
    output logic pin_tx,

    output logic led4,
    output logic led5
);

    // =========================================================================
    // Reset — POR (1 cycle) + key2 press (active low, synchronized)
    // =========================================================================
    logic por = 1'b1;
    always_ff @(posedge clk27) por <= 1'b0;

    logic key2_s1 = 1'b1, key2_s2 = 1'b1;
    always_ff @(posedge clk27) begin
        key2_s1 <= key2;
        key2_s2 <= key2_s1;
    end

    wire reset = por | ~key2_s2;

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

    // --- Slave 0: UART with integrated bootloader ---
    wire [31:0] bl_mem_addr;
    wire [ 7:0] bl_mem_data;
    wire        bl_mem_write;
    wire        bl_run;
    wire        bl_loading;

    uart_wb #(
        .BASE_ADDR(UART_ADR),
        .END_ADDR (UART_END)
    ) u_uart (
        .rx_pin      (pin_rx),
        .tx_pin      (pin_tx),
        .bus         (uart_bus),
        .bl_mem_addr (bl_mem_addr),
        .bl_mem_data (bl_mem_data),
        .bl_mem_write(bl_mem_write),
        .bl_run      (bl_run),
        .bl_loading  (bl_loading)
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
    // Status LEDs (active low: 0 = LED on)
    // =========================================================================
    assign led4 = !bl_loading;
    assign led5 = !bl_run;

endmodule
