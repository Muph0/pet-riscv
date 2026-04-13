// IF stage I/O
interface if_stage_io;

    logic        reset;

    // Pipeline control
    logic        stall;

    // UART loading interface
    logic [ 7:0] uart_data;
    logic        uart_valid;

    // To next stage
    logic [31:0] instr;  // fetched instruction
    logic [31:0] pc;  // PC associated with fetched instruction
    logic        loading;  // high while loading program from UART

    modport in(input reset, stall, uart_data, uart_valid, output instr, pc, loading);
    modport prev(input instr, pc);  // "prev" as seen by the next stage

endinterface


module if_stage
    import mem_pkg::*;
(
    input                  clk,
          if_stage_io.in   io,
          pc_stage_io.prev prev
);

    // --- State machine: LOADING vs FETCHING ---
    typedef enum logic {
        S_LOADING,
        S_FETCHING
    } state_t;

    state_t state;

    // Idle timeout: switch to FETCHING after no UART data for a while
    localparam int IDLE_TIMEOUT = 27_000_000 / 10;  // ~100ms at 27 MHz
    logic   [24:0] idle_counter;

    // UART byte accumulator → BSRAM write address
    logic   [31:0] load_addr;

    // BSRAM port mux signals
    logic   [31:0] mem_address;
    logic   [31:0] mem_data_in;
    width_t        mem_width;
    logic          mem_write_en;

    assign io.loading = (state == S_LOADING);

    always_comb begin
        if (state == S_LOADING) begin
            mem_address  = load_addr;
            mem_data_in  = {24'b0, io.uart_data};
            mem_width    = WIDTH_8;
            mem_write_en = io.uart_valid;
        end else begin
            mem_address  = prev.pc;
            mem_data_in  = '0;
            mem_width    = WIDTH_32;
            mem_write_en = '0;
        end
    end

    // --- State machine ---
    always_ff @(posedge clk) begin
        if (io.reset) begin
            state        <= S_LOADING;
            load_addr    <= '0;
            idle_counter <= '0;
        end else begin
            case (state)
                S_LOADING: begin
                    if (io.uart_valid) begin
                        load_addr    <= load_addr + 1'b1;
                        idle_counter <= '0;
                    end else begin
                        idle_counter <= idle_counter + 1'b1;
                    end

                    if (idle_counter >= IDLE_TIMEOUT[24:0] && load_addr != '0) state <= S_FETCHING;
                end
                S_FETCHING: ;  // normal operation
                default: state <= S_LOADING;
            endcase
        end
    end

    // --- Pipeline register: delay PC to match BSRAM latency ---
    always_ff @(posedge clk) begin
        if (io.reset) io.pc <= '0;
        else if (!io.stall && state == S_FETCHING) io.pc <= prev.pc;
    end

    // --- Instruction memory ---
    bsram32 #(
        .BYTES(8192)
    ) instr_mem (
        .clk     (clk),
        .address (mem_address),
        .data_in (mem_data_in),
        .width   (mem_width),
        .write_en(mem_write_en),
        .data_out(io.instr),
        .error   ()
    );

endmodule
