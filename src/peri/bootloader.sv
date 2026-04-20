// The bootloader takes control over the whole SoC on powerup.
// It receives a program via UART ('W' command), can verify
// CRC32 ('C' command), and releases the CPU ('D' command).
// After 'D' the bootloader enters S_DONE and is permanently
// disabled until the next reset (e.g. Silicone Key 1).
module bootloader (
    input clk,
    input reset,

    // UART RX interface (shared with MMIO)
    input [7:0] uart_data,
    input       uart_valid,

    // UART TX interface (CRC32 response)
    output logic [7:0] tx_data,
    output logic       tx_start,
    input              tx_busy,

    // Memory write port (directly drives IF stage BSRAM)
    output logic [31:0] mem_addr,
    output logic [ 7:0] mem_data,
    output logic        mem_write,

    // Pipeline control
    output logic run,
    output logic loading
);

    typedef enum logic [2:0] {
        S_IDLE,
        S_WRITE_A1,
        S_WRITE_A0,
        S_WRITE_DATA,
        S_CRC_SEND,
        S_DONE
    } state_t;

    state_t        state;
    logic   [15:0] byte_count;
    logic   [15:0] bytes_remaining;
    logic   [31:0] crc_reg;
    logic   [ 1:0] crc_byte_idx;

    assign loading   = (state != S_IDLE) && (state != S_DONE);
    assign mem_write = (state == S_WRITE_DATA) && uart_valid;
    assign mem_data  = uart_data;

    // CRC32 — Ethernet polynomial (reflected)
    function automatic logic [31:0] crc32_byte(input logic [31:0] crc_in, input logic [7:0] data);
        logic [31:0] c;
        c = crc_in ^ {24'd0, data};
        for (int i = 0; i < 8; i++) c = c[0] ? ((c >> 1) ^ 32'hEDB88320) : (c >> 1);
        return c;
    endfunction

    wire [31:0] crc_out = crc_reg ^ 32'hFFFF_FFFF;

    always_ff @(posedge clk) begin
        if (reset) begin
            state           <= S_IDLE;
            mem_addr        <= '0;
            byte_count      <= '0;
            bytes_remaining <= '0;
            run             <= '0;
            crc_reg         <= 32'hFFFF_FFFF;
            crc_byte_idx    <= '0;
            tx_start        <= '0;
            tx_data         <= '0;
        end else begin
            tx_start <= '0;

            case (state)
                S_IDLE: begin
                    if (uart_valid) begin
                        case (uart_data)
                            8'h57: begin  // 'W' write
                                state   <= S_WRITE_A1;
                                crc_reg <= 32'hFFFF_FFFF;
                            end
                            8'h43: begin  // 'C' check CRC
                                state        <= S_CRC_SEND;
                                crc_byte_idx <= '0;
                            end
                            8'h44: begin  // 'D' done
                                run   <= '1;
                                state <= S_DONE;
                            end
                            default: ;
                        endcase
                    end
                end

                S_WRITE_A1: begin
                    if (uart_valid) begin
                        byte_count[15:8] <= uart_data;
                        state            <= S_WRITE_A0;
                    end
                end

                S_WRITE_A0: begin
                    if (uart_valid) begin
                        byte_count[7:0] <= uart_data;
                        bytes_remaining <= {byte_count[15:8], uart_data};
                        mem_addr        <= '0;
                        state           <= S_WRITE_DATA;
                    end
                end

                S_WRITE_DATA: begin
                    if (uart_valid) begin
                        mem_addr        <= mem_addr + 1'b1;
                        bytes_remaining <= bytes_remaining - 1'b1;
                        crc_reg         <= crc32_byte(crc_reg, uart_data);
                        if (bytes_remaining == 16'd1) state <= S_IDLE;
                    end
                end

                S_CRC_SEND: begin
                    if (!tx_busy && !tx_start) begin
                        case (crc_byte_idx)
                            2'd0: tx_data <= crc_out[7:0];
                            2'd1: tx_data <= crc_out[15:8];
                            2'd2: tx_data <= crc_out[23:16];
                            2'd3: tx_data <= crc_out[31:24];
                        endcase
                        tx_start <= 1'b1;
                        if (crc_byte_idx == 2'd3) state <= S_IDLE;
                        else crc_byte_idx <= crc_byte_idx + 1'b1;
                    end
                end

                S_DONE: ;  // permanently disabled until reset

                default: state <= S_IDLE;
            endcase
        end
    end

endmodule
