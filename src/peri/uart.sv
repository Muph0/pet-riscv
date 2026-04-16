// =============================================================================
// 8N1 UART receiver
// =============================================================================
module uart_rx (
    input  logic        clk,
    input  logic        reset,
    input  logic        rx0,
    input  logic [15:0] bit_len,
    output logic [ 7:0] data_out,
    output logic        data_valid
);

    typedef enum logic [2:0] {
        READY,
        START,
        DATA,
        STOP
    } state_t;

    (* syn_encoding = "onehot" *) state_t s;
    logic [15:0] middle_counter;
    logic [2:0] bit_index;
    logic [7:0] buffer;
    logic rx1, rx;

    wire is_middle = middle_counter >= bit_len;

    always_ff @(posedge clk) begin
        if (reset) begin
            s <= READY;
            rx1 <= '1;
            rx <= '1;
            data_valid <= '0;
            data_out <= '0;
            middle_counter <= '0;

        end else begin
            rx1 <= rx0;
            rx <= rx1;
            data_valid <= '0;

            if (s != READY) middle_counter <= is_middle ? '0 : middle_counter + 1'd1;

            unique case (s)
                READY: begin
                    if (rx == '0) begin
                        middle_counter <= {1'b0, bit_len[15:1]};
                        s <= START;
                    end
                end
                START: begin
                    if (is_middle) begin
                        bit_index <= 0;
                        s <= DATA;
                    end
                end
                DATA: begin
                    if (is_middle) begin
                        data_valid <= '0;
                        bit_index <= bit_index + 1'd1;
                        buffer <= {rx, buffer[7:1]};
                        if (bit_index == 7) begin
                            s <= STOP;
                            data_out <= {rx, buffer[7:1]};
                        end
                    end
                end
                STOP: begin
                    if (is_middle) begin
                        data_valid <= rx == '1;
                        s <= READY;
                    end
                end
            endcase
        end
    end

endmodule


// =============================================================================
// 8N1 UART transmitter
// =============================================================================
module uart_tx (
    input  logic        clk,
    input  logic        reset,
    input  logic [ 7:0] data_in,
    input  logic        data_valid,  // pulse: load data_in and start transmitting
    input  logic [15:0] bit_len,
    output logic        tx0,
    output logic        busy
);

    typedef enum logic [2:0] {
        IDLE,
        START,
        DATA,
        STOP
    } state_t;

    (* syn_encoding = "onehot" *) state_t s;
    logic [15:0] counter;
    logic [2:0] bit_index;
    logic [7:0] shift_reg;

    wire tick = counter >= bit_len;

    always_ff @(posedge clk) begin
        if (reset) begin
            s         <= IDLE;
            tx0       <= '1;
            busy      <= '0;
            counter   <= '0;
            bit_index <= '0;
            shift_reg <= '0;

        end else begin
            if (s != IDLE) counter <= tick ? '0 : counter + 1'd1;

            unique case (s)
                IDLE: begin
                    tx0 <= '1;
                    if (data_valid) begin
                        shift_reg <= data_in;
                        busy      <= '1;
                        counter   <= '0;
                        s         <= START;
                    end
                end
                START: begin
                    tx0 <= '0;  // start bit
                    if (tick) begin
                        bit_index <= '0;
                        s         <= DATA;
                    end
                end
                DATA: begin
                    tx0 <= shift_reg[0];
                    if (tick) begin
                        shift_reg <= {1'b0, shift_reg[7:1]};
                        bit_index <= bit_index + 1'd1;
                        if (bit_index == 7) s <= STOP;
                    end
                end
                STOP: begin
                    tx0 <= '1;  // stop bit
                    if (tick) begin
                        busy <= '0;
                        s    <= IDLE;
                    end
                end
            endcase
        end
    end

endmodule


// =============================================================================
// Wishbone slave wrapper for UART RX + TX
// =============================================================================
module uart_wb #(
    parameter logic [31:0] BASE_ADDR = 32'h1000_0000,
    parameter logic [31:0] END_ADDR  = 32'h1000_0010
) (
    input rx_pin,
    output tx_pin,
    wishbone.slave bus
);

    wire         clk = bus.clk;
    wire         reset = bus.reset;

    // Local address (byte offset from BASE_ADDR)
    wire  [31:0] local_addr = bus.adr - BASE_ADDR;

    // --- MMIO registers ---
    // +0x0  TX_DATA / RX_DATA  (W: write byte to TX FIFO, R: read last RX byte)
    logic [ 7:0] tx_data;
    logic [ 7:0] rx_data;
    // +0x4  STATUS             (R: bit 0 = TX busy, bit 1 = RX data available)
    logic [ 1:0] status;
    // +0x8  CONTROL            (R/W: bit 0 = TX en, bit 1 = RX en, bit 2 = IRQ en)
    logic [ 2:0] control;
    // +0xC  BIT_LEN            (R/W: clock ticks per bit)
    logic [15:0] bit_len;
    // +0x10 -END-

    // --- TX signals ---
    logic        tx_start;
    wire         tx_busy;

    // --- RX signals ---
    wire  [ 7:0] rx_byte;
    wire         rx_valid;

    // --- Sub-modules ---
    uart_rx u_rx (
        .clk,
        .reset,
        .rx0       (rx_pin),
        .bit_len,
        .data_out  (rx_byte),
        .data_valid(rx_valid)
    );

    uart_tx u_tx (
        .clk,
        .reset,
        .data_in   (tx_data),
        .data_valid(tx_start),
        .bit_len,
        .tx0       (tx_pin),
        .busy      (tx_busy)
    );

    // --- Wishbone handshake ---
    wire  wb_active = bus.cyc & bus.stb;

    // Single-cycle ack
    logic ack_r;
    always_ff @(posedge clk) begin
        if (reset) ack_r <= '0;
        else ack_r <= wb_active & ~ack_r;  // ack for one cycle, then deassert
    end
    assign bus.ack = ack_r;
    assign bus.err = '0;
    assign bus.rty = '0;

    // --- Read mux ---
    always_comb begin
        bus.stom = '0;
        case (local_addr[3:2])
            2'd0: bus.stom = {24'd0, rx_data};
            2'd1: bus.stom = {30'd0, status};
            2'd2: bus.stom = {29'd0, control};
            2'd3: bus.stom = {16'd0, bit_len};
        endcase
    end

    // --- Write logic + status tracking ---
    always_ff @(posedge clk) begin
        tx_start <= '0;  // single-cycle pulse

        if (reset) begin
            status  <= '0;
            tx_data <= '0;
            rx_data <= '0;
            control <= '0;
            bit_len <= 16'(27_000_000 / 115_200);
        end else begin
            // Capture incoming RX byte
            if (rx_valid) begin
                rx_data   <= rx_byte;
                status[1] <= 1'b1;
            end

            // Track TX busy
            status[0] <= tx_busy;

            // Wishbone write
            if (wb_active & bus.we & ~ack_r) begin
                case (local_addr[3:2])
                    2'd0: begin
                        tx_data  <= bus.mtos[7:0];
                        tx_start <= 1'b1;
                    end
                    // 2'd1: status is read-only
                    2'd2: control <= bus.mtos[2:0];
                    2'd3: bit_len <= bus.mtos[15:0];
                endcase
            end

            // Clear RX-full on read of data register
            if (wb_active & ~bus.we & ~ack_r && local_addr[3:2] == 2'd0) status[1] <= 1'b0;
        end
    end

endmodule
