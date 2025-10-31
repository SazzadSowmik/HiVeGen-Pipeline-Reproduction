module OutputAccumulatorC (
    input  logic clk,
    input  logic rst_n
);
    parameter ROWS = 4;
    parameter COLS = 64;
    parameter DATA_WIDTH = 32;
    parameter DEPTH = 2;

    logic [DATA_WIDTH-1:0] accum_buffer [0:DEPTH-1][0:ROWS-1][0:COLS-1];
    logic [DATA_WIDTH-1:0] pe_partial_sum [0:ROWS-1][0:COLS-1];
    logic [DATA_WIDTH-1:0] final_output   [0:ROWS-1][0:COLS-1];
    logic [0:0] active_buf;
    logic accumulate_enable;
    logic writeback_enable;

    typedef enum logic [1:0] {
        IDLE,
        ACCUMULATE,
        WRITEBACK
    } state_t;

    state_t state, next_state;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            state <= IDLE;
        else
            state <= next_state;
    end

    always_comb begin
        next_state = state;
        accumulate_enable = 1'b0;
        writeback_enable  = 1'b0;
        case (state)
            IDLE: begin
                next_state = ACCUMULATE;
            end
            ACCUMULATE: begin
                accumulate_enable = 1'b1;
                next_state = WRITEBACK;
            end
            WRITEBACK: begin
                writeback_enable = 1'b1;
                next_state = IDLE;
            end
        endcase
    end

    integer i, j, d;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            active_buf <= 0;
            for (d = 0; d < DEPTH; d = d + 1) begin
                for (i = 0; i < ROWS; i = i + 1) begin
                    for (j = 0; j < COLS; j = j + 1) begin
                        accum_buffer[d][i][j] <= '0;
                    end
                end
            end
            for (i = 0; i < ROWS; i = i + 1) begin
                for (j = 0; j < COLS; j = j + 1) begin
                    final_output[i][j] <= '0;
                    pe_partial_sum[i][j] <= '0;
                end
            end
        end else begin
            if (accumulate_enable) begin
                for (i = 0; i < ROWS; i = i + 1) begin
                    for (j = 0; j < COLS; j = j + 1) begin
                        accum_buffer[active_buf][i][j] <= accum_buffer[active_buf][i][j] + pe_partial_sum[i][j];
                    end
                end
            end else if (writeback_enable) begin
                for (i = 0; i < ROWS; i = i + 1) begin
                    for (j = 0; j < COLS; j = j + 1) begin
                        final_output[i][j] <= accum_buffer[active_buf][i][j];
                    end
                end
                active_buf <= ~active_buf;
                for (i = 0; i < ROWS; i = i + 1) begin
                    for (j = 0; j < COLS; j = j + 1) begin
                        accum_buffer[active_buf][i][j] <= '0;
                    end
                end
            end
        end
    end

endmodule