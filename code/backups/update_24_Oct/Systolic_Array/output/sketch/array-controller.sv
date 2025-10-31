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