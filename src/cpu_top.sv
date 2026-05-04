module cpu_top (
    input logic clk27,  // 27 MHz oscillator
    input logic key2,   // Silicone Key 2 (active low) — resets bootloader

    input  logic pin_rx,
    output logic pin_tx,

    output logic led4,
    output logic led5,

    wishbone.master ext_ddr_bus,
    input logic [1:0] ext_ddr_status
);
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
    localparam logic [31:0] BRAM_ADR = 32'h0000_4000;
    localparam logic [31:0] BRAM_END = 32'h0000_7FFF;
    localparam logic [31:0] BUSI_ADR = 32'h1000_0000;
    localparam logic [31:0] BUSI_END = 32'h1000_002F;
    localparam logic [31:0] UART_ADR = 32'h1001_0000;
    localparam logic [31:0] UART_END = 32'h1001_000F;
    localparam logic [31:0] DDR__ADR = 32'h8000_0000;
    localparam logic [31:0] DDR__END = 32'h87FF_FFFF;

    // --- Named master interfaces ---
    wishbone core_ibus (
        .clk  (clk27),
        .reset(reset)
    );  // core Pipeline IF master
    wishbone xbar_ibus (
        .clk  (clk27),
        .reset(reset)
    );  // M0: xbar instruction fetch
    wishbone dbus (
        .clk  (clk27),
        .reset(reset)
    );  // M1: load/store

    // --- Named slave interfaces ---
    wishbone busi_bus (
        .clk  (clk27),
        .reset(reset)
    );
    wishbone uart_bus (
        .clk  (clk27),
        .reset(reset)
    );  // S0: UART MMIO
    wishbone bsram_bus (
        .clk  (clk27),
        .reset(reset)
    );  // S1: on-chip BRAM (Port B)
    wishbone rom_bus (
        .clk  (clk27),
        .reset(reset)
    );  // bypassed BRAM (Port A)

    // --- ibus Harvard Splitter ---
    wire ibus_is_bram = (core_ibus.adr >= BRAM_ADR) && (core_ibus.adr <= BRAM_END);

    // MUX core_ibus -> rom_bus (BRAM Port A)
    assign rom_bus.adr = core_ibus.adr;
    assign rom_bus.mtos = core_ibus.mtos;
    assign rom_bus.sel = core_ibus.sel;
    assign rom_bus.we = core_ibus.we;
    assign rom_bus.cyc = core_ibus.cyc & ibus_is_bram;
    assign rom_bus.stb = core_ibus.stb & ibus_is_bram;

    // MUX core_ibus -> xbar_ibus (Main Crossbar)
    assign xbar_ibus.adr = core_ibus.adr;
    assign xbar_ibus.mtos = core_ibus.mtos;
    assign xbar_ibus.sel = core_ibus.sel;
    assign xbar_ibus.we = core_ibus.we;
    assign xbar_ibus.cyc = core_ibus.cyc & ~ibus_is_bram;
    assign xbar_ibus.stb = core_ibus.stb & ~ibus_is_bram;

    // Return signals to core_ibus
    assign core_ibus.stom = ibus_is_bram ? rom_bus.stom : xbar_ibus.stom;
    assign core_ibus.ack = ibus_is_bram ? rom_bus.ack : xbar_ibus.ack;
    assign core_ibus.err = ibus_is_bram ? rom_bus.err : xbar_ibus.err;
    assign core_ibus.rty = ibus_is_bram ? rom_bus.rty : xbar_ibus.rty;

    bus_xbar_ctrl #(
        .NM     (2),
        .NS     (4),
        .S_START('{BUSI_ADR, UART_ADR, DDR__ADR, BRAM_ADR}),
        .S_END  ('{BUSI_END, UART_END, DDR__END, BRAM_END})
    ) xbar (
        .m_bus('{xbar_ibus, dbus}),
        .s_bus('{busi_bus, uart_bus, ext_ddr_bus, bsram_bus})
    );

    // --- Slave: Bus Info Peripheral ---
    logic [1:0] ddr_status; // Wait, actually ddr_status should come from wb_ddr3 via top. Let's make it an input port to cpu_top
    businfo_wb #(
        .BASE_ADDR(BUSI_ADR),
        .END_ADDR (BUSI_END)
    ) u_businfo (
        .bus(busi_bus),
        .ddr_status(ext_ddr_status)
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
        .PC_RESET(BRAM_ADR)
    ) pipe (
        .clk  (clk27),
        .reset(reset),
        .halt (!bl_run),
        .ibus (core_ibus),
        .dbus (dbus)
    );

    // =========================================================================
    // Status LEDs (active low: 0 = LED on)
    // =========================================================================
    assign led4 = !bl_loading;
    assign led5 = !bl_run;

endmodule
