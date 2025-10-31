
// ---- ArrayController ----
module ArrayController (
    input  logic clk,
    input  logic rst_n
);
    parameter M = 4;
    parameter N = 4;
    parameter K = 4;
    parameter DATA_WIDTH = 32;

    typedef enum logic [2:0] {
        IDLE,
        LOAD_TILE,
        COMPUTE,
        STORE_TILE,
        NEXT_LOOP,
        DONE
    } state_t;

    state_t state, next_state;

    logic [DATA_WIDTH-1:0] buffer_A [0:M-1][0:K-1];
    logic [DATA_WIDTH-1:0] buffer_B [0:K-1][0:N-1];
    logic [DATA_WIDTH-1:0] buffer_C [0:M-1][0:N-1];
    logic [DATA_WIDTH-1:0] pe_output  [0:M-1][0:N-1];

    logic [15:0] m_cnt, n_cnt, k_cnt;
    logic pe_enable;
    logic tile_done;
    logic all_done;

    integer i, j, k;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            state <= IDLE;
        else
            state <= next_state;
    end

    always_comb begin
        next_state = state;
        pe_enable = 1'b0;
        tile_done = 1'b0;
        all_done  = 1'b0;
        case (state)
            IDLE: begin
                next_state = LOAD_TILE;
            end
            LOAD_TILE: begin
                next_state = COMPUTE;
            end
            COMPUTE: begin
                pe_enable = 1'b1;
                next_state = STORE_TILE;
            end
            STORE_TILE: begin
                tile_done = 1'b1;
                next_state = NEXT_LOOP;
            end
            NEXT_LOOP: begin
                if ((m_cnt == M-1) && (n_cnt == N-1) && (k_cnt == K-1))
                    next_state = DONE;
                else
                    next_state = LOAD_TILE;
            end
            DONE: begin
                all_done = 1'b1;
                next_state = IDLE;
            end
        endcase
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            m_cnt <= 0;
            n_cnt <= 0;
            k_cnt <= 0;
            for (i = 0; i < M; i = i + 1) begin
                for (j = 0; j < N; j = j + 1) begin
                    buffer_C[i][j] <= '0;
                    pe_output[i][j] <= '0;
                end
            end
            for (i = 0; i < M; i = i + 1) begin
                for (k = 0; k < K; k = k + 1) begin
                    buffer_A[i][k] <= '0;
                end
            end
            for (k = 0; k < K; k = k + 1) begin
                for (j = 0; j < N; j = j + 1) begin
                    buffer_B[k][j] <= '0;
                end
            end
        end else begin
            case (state)
                LOAD_TILE: begin
                    for (i = 0; i < M; i = i + 1) begin
                        for (k = 0; k < K; k = k + 1) begin
                            buffer_A[i][k] <= buffer_A[i][k] + 1;
                        end
                    end
                    for (k = 0; k < K; k = k + 1) begin
                        for (j = 0; j < N; j = j + 1) begin
                            buffer_B[k][j] <= buffer_B[k][j] + 1;
                        end
                    end
                end
                COMPUTE: begin
                    if (pe_enable) begin
                        for (i = 0; i < M; i = i + 1) begin
                            for (j = 0; j < N; j = j + 1) begin
                                pe_output[i][j] <= '0;
                                for (k = 0; k < K; k = k + 1) begin
                                    pe_output[i][j] <= pe_output[i][j] + buffer_A[i][k] * buffer_B[k][j];
                                end
                            end
                        end
                    end
                end
                STORE_TILE: begin
                    if (tile_done) begin
                        for (i = 0; i < M; i = i + 1) begin
                            for (j = 0; j < N; j = j + 1) begin
                                buffer_C[i][j] <= pe_output[i][j];
                            end
                        end
                    end
                end
                NEXT_LOOP: begin
                    if (k_cnt < K-1)
                        k_cnt <= k_cnt + 1;
                    else begin
                        k_cnt <= 0;
                        if (n_cnt < N-1)
                            n_cnt <= n_cnt + 1;
                        else begin
                            n_cnt <= 0;
                            if (m_cnt < M-1)
                                m_cnt <= m_cnt + 1;
                            else
                                m_cnt <= 0;
                        end
                    end
                end
                DONE: begin
                    all_done <= 1'b1;
                end
            endcase
        end
    end

endmodule

// ---- InputBufferA ----
module InputBufferA (
    input  logic clk,
    input  logic rst_n
);
    parameter ROWS = 4;
    parameter COLS = 64;
    parameter DATA_WIDTH = 16;

    logic [DATA_WIDTH-1:0] line_buffer [0:ROWS-1][0:COLS-1];
    logic [5:0] write_ptr [0:ROWS-1];
    logic [5:0] read_ptr  [0:ROWS-1];
    logic [DATA_WIDTH-1:0] input_data [0:ROWS-1];
    logic [DATA_WIDTH-1:0] output_data [0:ROWS-1];
    logic load_enable;
    logic stream_enable;

    typedef enum logic [1:0] {
        IDLE,
        LOAD,
        STREAM
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
        load_enable = 1'b0;
        stream_enable = 1'b0;
        case (state)
            IDLE: begin
                next_state = LOAD;
            end
            LOAD: begin
                load_enable = 1'b1;
                if (&write_ptr[0])
                    next_state = STREAM;
            end
            STREAM: begin
                stream_enable = 1'b1;
                if (&read_ptr[0])
                    next_state = IDLE;
            end
        endcase
    end

    integer i, j;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (i = 0; i < ROWS; i = i + 1) begin
                write_ptr[i] <= 0;
                read_ptr[i] <= 0;
                for (j = 0; j < COLS; j = j + 1) begin
                    line_buffer[i][j] <= '0;
                end
            end
        end else begin
            if (load_enable) begin
                for (i = 0; i < ROWS; i = i + 1) begin
                    line_buffer[i][write_ptr[i]] <= input_data[i];
                    if (write_ptr[i] < COLS-1)
                        write_ptr[i] <= write_ptr[i] + 1;
                    else
                        write_ptr[i] <= 0;
                end
            end else if (stream_enable) begin
                for (i = 0; i < ROWS; i = i + 1) begin
                    output_data[i] <= line_buffer[i][read_ptr[i]];
                    if (read_ptr[i] < COLS-1)
                        read_ptr[i] <= read_ptr[i] + 1;
                    else
                        read_ptr[i] <= 0;
                end
            end
        end
    end

endmodule

// ---- InputBufferB ----
module InputBufferB (
    input  logic clk,
    input  logic rst_n
);
    parameter COLS = 4;
    parameter ROWS = 64;
    parameter DATA_WIDTH = 16;

    logic [DATA_WIDTH-1:0] line_buffer [0:COLS-1][0:ROWS-1];
    logic [5:0] write_ptr [0:COLS-1];
    logic [5:0] read_ptr  [0:COLS-1];
    logic [DATA_WIDTH-1:0] input_data [0:COLS-1];
    logic [DATA_WIDTH-1:0] output_data [0:COLS-1];
    logic load_enable;
    logic stream_enable;

    typedef enum logic [1:0] {
        IDLE,
        LOAD,
        STREAM
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
        load_enable = 1'b0;
        stream_enable = 1'b0;
        case (state)
            IDLE: begin
                next_state = LOAD;
            end
            LOAD: begin
                load_enable = 1'b1;
                if (&write_ptr[0])
                    next_state = STREAM;
            end
            STREAM: begin
                stream_enable = 1'b1;
                if (&read_ptr[0])
                    next_state = IDLE;
            end
        endcase
    end

    integer i, j;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (i = 0; i < COLS; i = i + 1) begin
                write_ptr[i] <= 0;
                read_ptr[i] <= 0;
                for (j = 0; j < ROWS; j = j + 1) begin
                    line_buffer[i][j] <= '0;
                end
            end
        end else begin
            if (load_enable) begin
                for (i = 0; i < COLS; i = i + 1) begin
                    line_buffer[i][write_ptr[i]] <= input_data[i];
                    if (write_ptr[i] < ROWS-1)
                        write_ptr[i] <= write_ptr[i] + 1;
                    else
                        write_ptr[i] <= 0;
                end
            end else if (stream_enable) begin
                for (i = 0; i < COLS; i = i + 1) begin
                    output_data[i] <= line_buffer[i][read_ptr[i]];
                    if (read_ptr[i] < ROWS-1)
                        read_ptr[i] <= read_ptr[i] + 1;
                    else
                        read_ptr[i] <= 0;
                end
            end
        end
    end

endmodule

// ---- OutputAccumulatorC ----
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

// ---- ProcessingElement ----
module ProcessingElement (
    input  logic clk,
    input  logic rst_n
);
    parameter DATA_WIDTH = 16;
    parameter ACC_WIDTH  = 32;

    logic signed [DATA_WIDTH-1:0] a_in;
    logic signed [DATA_WIDTH-1:0] b_in;
    logic signed [DATA_WIDTH-1:0] a_out;
    logic signed [DATA_WIDTH-1:0] b_out;
    logic signed [ACC_WIDTH-1:0]  partial_sum_in;
    logic signed [ACC_WIDTH-1:0]  partial_sum_out;

    logic signed [DATA_WIDTH-1:0] a_reg;
    logic signed [DATA_WIDTH-1:0] b_reg;
    logic signed [ACC_WIDTH-1:0]  psum_reg;
    logic signed [ACC_WIDTH-1:0]  mult_result;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            a_reg <= '0;
            b_reg <= '0;
            psum_reg <= '0;
            mult_result <= '0;
            a_out <= '0;
            b_out <= '0;
            partial_sum_out <= '0;
        end else begin
            a_reg <= a_in;
            b_reg <= b_in;
            mult_result <= a_reg * b_reg;
            psum_reg <= partial_sum_in + mult_result;
            a_out <= a_reg;
            b_out <= b_reg;
            partial_sum_out <= psum_reg;
        end
    end
endmodule

// ---- PE_Array_4x4 ----
module PE_Array_4x4 (
    input  logic clk,
    input  logic rst_n
);
    parameter DATA_WIDTH = 32;
    parameter SIZE = 4;

    logic [DATA_WIDTH-1:0] a_in [0:SIZE-1][0:SIZE-1];
    logic [DATA_WIDTH-1:0] b_in [0:SIZE-1][0:SIZE-1];
    logic [DATA_WIDTH-1:0] sum   [0:SIZE-1][0:SIZE-1];
    logic [DATA_WIDTH-1:0] a_out [0:SIZE-1][0:SIZE-1];
    logic [DATA_WIDTH-1:0] b_out [0:SIZE-1][0:SIZE-1];

    genvar i, j;
    generate
        for (i = 0; i < SIZE; i = i + 1) begin : row_gen
            for (j = 0; j < SIZE; j = j + 1) begin : col_gen
                ProcessingElement pe_inst (
                    .clk(clk),
                    .rst_n(rst_n)
                );
            end
        end
    endgenerate

    integer r, c;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (r = 0; r < SIZE; r = r + 1) begin
                for (c = 0; c < SIZE; c = c + 1) begin
                    a_in[r][c] <= '0;
                    b_in[r][c] <= '0;
                    sum[r][c]  <= '0;
                    a_out[r][c] <= '0;
                    b_out[r][c] <= '0;
                end
            end
        end else begin
            for (r = 0; r < SIZE; r = r + 1) begin
                for (c = 0; c < SIZE; c = c + 1) begin
                    if (r == 0)
                        a_in[r][c] <= a_out[r][c];
                    else
                        a_in[r][c] <= a_out[r-1][c];
                    if (c == 0)
                        b_in[r][c] <= b_out[r][c];
                    else
                        b_in[r][c] <= b_out[r][c-1];
                    sum[r][c] <= sum[r][c] + (a_in[r][c] * b_in[r][c]);
                    a_out[r][c] <= a_in[r][c];
                    b_out[r][c] <= b_in[r][c];
                end
            end
        end
    end
endmodule

// ---- MemoryInterface ----
module MemoryInterface (
    input  logic clk,
    input  logic rst_n
);
    parameter ROWS = 4;
    parameter COLS = 64;
    parameter DATA_WIDTH = 16;

    logic [DATA_WIDTH-1:0] bufferA [0:ROWS-1][0:COLS-1];
    logic [DATA_WIDTH-1:0] bufferB [0:ROWS-1][0:COLS-1];
    logic [DATA_WIDTH-1:0] bufferC [0:ROWS-1][0:COLS-1];

    logic [5:0] write_ptrA [0:ROWS-1];
    logic [5:0] read_ptrA  [0:ROWS-1];
    logic [5:0] write_ptrB [0:ROWS-1];
    logic [5:0] read_ptrB  [0:ROWS-1];
    logic [5:0] write_ptrC [0:ROWS-1];
    logic [5:0] read_ptrC  [0:ROWS-1];

    logic [DATA_WIDTH-1:0] input_dataA [0:ROWS-1];
    logic [DATA_WIDTH-1:0] input_dataB [0:ROWS-1];
    logic [DATA_WIDTH-1:0] input_dataC [0:ROWS-1];
    logic [DATA_WIDTH-1:0] output_dataA [0:ROWS-1];
    logic [DATA_WIDTH-1:0] output_dataB [0:ROWS-1];
    logic [DATA_WIDTH-1:0] output_dataC [0:ROWS-1];

    logic load_enableA, load_enableB, load_enableC;
    logic stream_enableA, stream_enableB, stream_enableC;

    typedef enum logic [1:0] {
        IDLE,
        LOAD,
        STREAM
    } state_t;

    state_t stateA, next_stateA;
    state_t stateB, next_stateB;
    state_t stateC, next_stateC;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            stateA <= IDLE;
            stateB <= IDLE;
            stateC <= IDLE;
        end else begin
            stateA <= next_stateA;
            stateB <= next_stateB;
            stateC <= next_stateC;
        end
    end

    always_comb begin
        next_stateA = stateA;
        next_stateB = stateB;
        next_stateC = stateC;
        load_enableA = 1'b0;
        load_enableB = 1'b0;
        load_enableC = 1'b0;
        stream_enableA = 1'b0;
        stream_enableB = 1'b0;
        stream_enableC = 1'b0;

        case (stateA)
            IDLE: next_stateA = LOAD;
            LOAD: begin
                load_enableA = 1'b1;
                if (&write_ptrA[0]) next_stateA = STREAM;
            end
            STREAM: begin
                stream_enableA = 1'b1;
                if (&read_ptrA[0]) next_stateA = IDLE;
            end
        endcase

        case (stateB)
            IDLE: next_stateB = LOAD;
            LOAD: begin
                load_enableB = 1'b1;
                if (&write_ptrB[0]) next_stateB = STREAM;
            end
            STREAM: begin
                stream_enableB = 1'b1;
                if (&read_ptrB[0]) next_stateB = IDLE;
            end
        endcase

        case (stateC)
            IDLE: next_stateC = LOAD;
            LOAD: begin
                load_enableC = 1'b1;
                if (&write_ptrC[0]) next_stateC = STREAM;
            end
            STREAM: begin
                stream_enableC = 1'b1;
                if (&read_ptrC[0]) next_stateC = IDLE;
            end
        endcase
    end

    integer i, j;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (i = 0; i < ROWS; i = i + 1) begin
                write_ptrA[i] <= 0;
                read_ptrA[i] <= 0;
                write_ptrB[i] <= 0;
                read_ptrB[i] <= 0;
                write_ptrC[i] <= 0;
                read_ptrC[i] <= 0;
                for (j = 0; j < COLS; j = j + 1) begin
                    bufferA[i][j] <= '0;
                    bufferB[i][j] <= '0;
                    bufferC[i][j] <= '0;
                end
            end
        end else begin
            if (load_enableA) begin
                for (i = 0; i < ROWS; i = i + 1) begin
                    bufferA[i][write_ptrA[i]] <= input_dataA[i];
                    if (write_ptrA[i] < COLS-1)
                        write_ptrA[i] <= write_ptrA[i] + 1;
                    else
                        write_ptrA[i] <= 0;
                end
            end else if (stream_enableA) begin
                for (i = 0; i < ROWS; i = i + 1) begin
                    output_dataA[i] <= bufferA[i][read_ptrA[i]];
                    if (read_ptrA[i] < COLS-1)
                        read_ptrA[i] <= read_ptrA[i] + 1;
                    else
                        read_ptrA[i] <= 0;
                end
            end

            if (load_enableB) begin
                for (i = 0; i < ROWS; i = i + 1) begin
                    bufferB[i][write_ptrB[i]] <= input_dataB[i];
                    if (write_ptrB[i] < COLS-1)
                        write_ptrB[i] <= write_ptrB[i] + 1;
                    else
                        write_ptrB[i] <= 0;
                end
            end else if (stream_enableB) begin
                for (i = 0; i < ROWS; i = i + 1) begin
                    output_dataB[i] <= bufferB[i][read_ptrB[i]];
                    if (read_ptrB[i] < COLS-1)
                        read_ptrB[i] <= read_ptrB[i] + 1;
                    else
                        read_ptrB[i] <= 0;
                end
            end

            if (load_enableC) begin
                for (i = 0; i < ROWS; i = i + 1) begin
                    bufferC[i][write_ptrC[i]] <= input_dataC[i];
                    if (write_ptrC[i] < COLS-1)
                        write_ptrC[i] <= write_ptrC[i] + 1;
                    else
                        write_ptrC[i] <= 0;
                end
            end else if (stream_enableC) begin
                for (i = 0; i < ROWS; i = i + 1) begin
                    output_dataC[i] <= bufferC[i][read_ptrC[i]];
                    if (read_ptrC[i] < COLS-1)
                        read_ptrC[i] <= read_ptrC[i] + 1;
                    else
                        read_ptrC[i] <= 0;
                end
            end
        end
    end

endmodule

// ---- ClockResetUnit ----
module ClockResetUnit (
    input  logic clk_in,
    input  logic rst_in,
    output logic clk_out,
    output logic rst_n_out
);
    parameter integer DIV_FACTOR = 2;
    parameter integer GATE_ENABLE = 1;

    logic [31:0] div_cnt;
    logic clk_div;
    logic clk_gated;
    logic rst_sync1, rst_sync2;

    always_ff @(posedge clk_in or posedge rst_in) begin
        if (rst_in) begin
            div_cnt <= 32'd0;
            clk_div <= 1'b0;
        end else begin
            if (div_cnt == (DIV_FACTOR/2 - 1)) begin
                clk_div <= ~clk_div;
                div_cnt <= 32'd0;
            end else begin
                div_cnt <= div_cnt + 32'd1;
            end
        end
    end

    always_ff @(posedge clk_div or posedge rst_in) begin
        if (rst_in) begin
            rst_sync1 <= 1'b0;
            rst_sync2 <= 1'b0;
        end else begin
            rst_sync1 <= 1'b1;
            rst_sync2 <= rst_sync1;
        end
    end

    always_comb begin
        if (GATE_ENABLE == 1)
            clk_gated = clk_div & rst_sync2;
        else
            clk_gated = clk_div;
    end

    assign clk_out = clk_gated;
    assign rst_n_out = rst_sync2;

endmodule

// ---- PerformanceMonitor ----
module PerformanceMonitor (
    input  logic clk,
    input  logic rst_n
);
    parameter COUNTER_WIDTH = 32;
    parameter WINDOW_SIZE   = 1024;

    typedef enum logic [2:0] {
        IDLE,
        MEASURE_UTIL,
        MEASURE_LAT,
        MEASURE_TPUT,
        UPDATE_STATS,
        DONE
    } state_t;

    state_t state, next_state;

    logic [COUNTER_WIDTH-1:0] cycle_count;
    logic [COUNTER_WIDTH-1:0] active_count;
    logic [COUNTER_WIDTH-1:0] latency_accum;
    logic [COUNTER_WIDTH-1:0] throughput_accum;
    logic [COUNTER_WIDTH-1:0] sample_count;

    logic [COUNTER_WIDTH-1:0] utilization;
    logic [COUNTER_WIDTH-1:0] avg_latency;
    logic [COUNTER_WIDTH-1:0] avg_throughput;

    logic measure_done;
    integer i, j;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            state <= IDLE;
        else
            state <= next_state;
    end

    always_comb begin
        next_state = state;
        measure_done = 1'b0;
        case (state)
            IDLE: begin
                next_state = MEASURE_UTIL;
            end
            MEASURE_UTIL: begin
                if (cycle_count >= WINDOW_SIZE)
                    next_state = MEASURE_LAT;
            end
            MEASURE_LAT: begin
                if (cycle_count >= WINDOW_SIZE*2)
                    next_state = MEASURE_TPUT;
            end
            MEASURE_TPUT: begin
                if (cycle_count >= WINDOW_SIZE*3)
                    next_state = UPDATE_STATS;
            end
            UPDATE_STATS: begin
                measure_done = 1'b1;
                next_state = DONE;
            end
            DONE: begin
                next_state = IDLE;
            end
        endcase
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cycle_count      <= '0;
            active_count     <= '0;
            latency_accum    <= '0;
            throughput_accum <= '0;
            sample_count     <= '0;
            utilization      <= '0;
            avg_latency      <= '0;
            avg_throughput   <= '0;
        end else begin
            cycle_count <= cycle_count + 1;
            case (state)
                MEASURE_UTIL: begin
                    active_count <= active_count + 1;
                end
                MEASURE_LAT: begin
                    latency_accum <= latency_accum + (cycle_count[7:0]);
                    sample_count  <= sample_count + 1;
                end
                MEASURE_TPUT: begin
                    throughput_accum <= throughput_accum + (cycle_count[7:0]);
                end
                UPDATE_STATS: begin
                    if (sample_count != 0) begin
                        utilization    <= (active_count * 100) / WINDOW_SIZE;
                        avg_latency    <= latency_accum / sample_count;
                        avg_throughput <= throughput_accum / sample_count;
                    end
                    for (i = 0; i < 1; i = i + 1) begin
                        for (j = 0; j < 1; j = j + 1) begin
                            cycle_count      <= '0;
                            active_count     <= '0;
                            latency_accum    <= '0;
                            throughput_accum <= '0;
                            sample_count     <= '0;
                        end
                    end
                end
                DONE: begin
                    if (measure_done) begin
                        for (i = 0; i < 1; i = i + 1) begin
                            for (j = 0; j < 1; j = j + 1) begin
                                utilization    <= utilization;
                                avg_latency    <= avg_latency;
                                avg_throughput <= avg_throughput;
                            end
                        end
                    end
                end
            endcase
        end
    end

endmodule

// ---- SystolicArray_GEMM_4x4 ----
module SystolicArray_GEMM_4x4 (
    input  logic clk,
    input  logic rst_n
);
    parameter M = 4;
    parameter N = 4;
    parameter K = 4;
    parameter DATA_WIDTH = 16;

    logic clk_int;
    logic rst_n_int;

    ClockResetUnit clk_rst_unit (
        .clk_in(clk),
        .rst_in(~rst_n),
        .clk_out(clk_int),
        .rst_n_out(rst_n_int)
    );

    logic [DATA_WIDTH-1:0] buffer_A [0:M-1][0:K-1];
    logic [DATA_WIDTH-1:0] buffer_B [0:K-1][0:N-1];
    logic [DATA_WIDTH-1:0] buffer_C [0:M-1][0:N-1];
    logic [DATA_WIDTH-1:0] pe_output [0:M-1][0:N-1];

    logic [15:0] m_cnt, n_cnt, k_cnt;
    logic pe_enable;
    logic tile_done;
    logic all_done;

    typedef enum logic [2:0] {
        IDLE,
        LOAD_TILE,
        COMPUTE,
        STORE_TILE,
        NEXT_LOOP,
        DONE
    } state_t;

    state_t state, next_state;

    integer i, j, k;

    always_ff @(posedge clk_int or negedge rst_n_int) begin
        if (!rst_n_int)
            state <= IDLE;
        else
            state <= next_state;
    end

    always_comb begin
        next_state = state;
        pe_enable = 1'b0;
        tile_done = 1'b0;
        all_done  = 1'b0;
        case (state)
            IDLE: begin
                next_state = LOAD_TILE;
            end
            LOAD_TILE: begin
                next_state = COMPUTE;
            end
            COMPUTE: begin
                pe_enable = 1'b1;
                next_state = STORE_TILE;
            end
            STORE_TILE: begin
                tile_done = 1'b1;
                next_state = NEXT_LOOP;
            end
            NEXT_LOOP: begin
                if ((m_cnt == M-1) && (n_cnt == N-1) && (k_cnt == K-1))
                    next_state = DONE;
                else
                    next_state = LOAD_TILE;
            end
            DONE: begin
                all_done = 1'b1;
                next_state = IDLE;
            end
        endcase
    end

    always_ff @(posedge clk_int or negedge rst_n_int) begin
        if (!rst_n_int) begin
            m_cnt <= 0;
            n_cnt <= 0;
            k_cnt <= 0;
            for (i = 0; i < M; i = i + 1) begin
                for (j = 0; j < N; j = j + 1) begin
                    buffer_C[i][j] <= '0;
                    pe_output[i][j] <= '0;
                end
            end
            for (i = 0; i < M; i = i + 1) begin
                for (k = 0; k < K; k = k + 1) begin
                    buffer_A[i][k] <= '0;
                end
            end
            for (k = 0; k < K; k = k + 1) begin
                for (j = 0; j < N; j = j + 1) begin
                    buffer_B[k][j] <= '0;
                end
            end
        end else begin
            case (state)
                LOAD_TILE: begin
                    for (i = 0; i < M; i = i + 1) begin
                        for (k = 0; k < K; k = k + 1) begin
                            buffer_A[i][k] <= buffer_A[i][k] + 1;
                        end
                    end
                    for (k = 0; k < K; k = k + 1) begin
                        for (j = 0; j < N; j = j + 1) begin
                            buffer_B[k][j] <= buffer_B[k][j] + 1;
                        end
                    end
                end
                COMPUTE: begin
                    if (pe_enable) begin
                        for (i = 0; i < M; i = i + 1) begin
                            for (j = 0; j < N; j = j + 1) begin
                                pe_output[i][j] <= '0;
                                for (k = 0; k < K; k = k + 1) begin
                                    pe_output[i][j] <= pe_output[i][j] + buffer_A[i][k] * buffer_B[k][j];
                                end
                            end
                        end
                    end
                end
                STORE_TILE: begin
                    if (tile_done) begin
                        for (i = 0; i < M; i = i + 1) begin
                            for (j = 0; j < N; j = j + 1) begin
                                buffer_C[i][j] <= pe_output[i][j];
                            end
                        end
                    end
                end
                NEXT_LOOP: begin
                    if (k_cnt < K-1)
                        k_cnt <= k_cnt + 1;
                    else begin
                        k_cnt <= 0;
                        if (n_cnt < N-1)
                            n_cnt <= n_cnt + 1;
                        else begin
                            n_cnt <= 0;
                            if (m_cnt < M-1)
                                m_cnt <= m_cnt + 1;
                            else
                                m_cnt <= 0;
                        end
                    end
                end
                DONE: begin
                    all_done <= 1'b1;
                end
            endcase
        end
    end

    ArrayController ctrl (.clk(clk_int), .rst_n(rst_n_int));
    InputBufferA bufA (.clk(clk_int), .rst_n(rst_n_int));
    InputBufferB bufB (.clk(clk_int), .rst_n(rst_n_int));
    OutputAccumulatorC bufC (.clk(clk_int), .rst_n(rst_n_int));
    PE_Array_4x4 pe_array (.clk(clk_int), .rst_n(rst_n_int));
    MemoryInterface memif (.clk(clk_int), .rst_n(rst_n_int));
    PerformanceMonitor perfmon (.clk(clk_int), .rst_n(rst_n_int));

endmodule
