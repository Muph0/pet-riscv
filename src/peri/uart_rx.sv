module uart_rx #(
    // parameter logic [15:0] CLKS_PER_BIT = 27_000_000 / 115_200 REMOVED in favor of bit length
) (
    input  logic        clk,
    input  logic        reset,
    input  logic        rx0,
    input  logic [15:0] bit_len,    // bit length in clock pulses
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

    wire is_middle = middle_counter >= CLKS_PER_BIT;

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
            data_valid <= '0;  // single-cycle pulse

            if (s != READY) middle_counter <= is_middle ? '0 : middle_counter + 1'd1;

            unique case (s)
                READY: begin
                    if (rx == '0) begin
                        middle_counter <= {1'b0, bit_len[15:1]};  // set timer to half-bit time
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
