module bootloader (
    input clk,
    input reset,

    // UART interface
    input [7:0] uart_data,
    input       uart_valid,

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
        S_WRITE_DATA
    } state_t;

    state_t        state;
    logic   [15:0] byte_count;
    logic   [15:0] bytes_remaining;

    assign loading   = (state != S_IDLE);
    assign mem_write = (state == S_WRITE_DATA) && uart_valid;
    assign mem_data  = uart_data;

    always_ff @(posedge clk) begin
        if (reset) begin
            state           <= S_IDLE;
            mem_addr        <= '0;
            byte_count      <= '0;
            bytes_remaining <= '0;
            run             <= '0;
        end else if (uart_valid) begin
            case (state)
                S_IDLE: begin
                    case (uart_data)
                        8'h57:  // 'W'
                        state <= S_WRITE_A1;
                        8'h52:  // 'R'
                        run <= '1;
                        default: ;
                    endcase
                end

                S_WRITE_A1: begin
                    byte_count[15:8] <= uart_data;
                    state            <= S_WRITE_A0;
                end

                S_WRITE_A0: begin
                    byte_count[7:0] <= uart_data;
                    bytes_remaining <= {byte_count[15:8], uart_data};
                    mem_addr        <= '0;
                    state           <= S_WRITE_DATA;
                end

                S_WRITE_DATA: begin
                    mem_addr        <= mem_addr + 1'b1;
                    bytes_remaining <= bytes_remaining - 1'b1;
                    if (bytes_remaining == 16'd1) state <= S_IDLE;
                end

                default: state <= S_IDLE;
            endcase
        end
    end

endmodule
