module SystolicArray_GEMM_4x4 (
    input  logic clk,
    input  logic rst_n
);
    localparam int N = 4;
    typedef logic signed [15:0] data_t;
    typedef logic signed [31:0] acc_t;

    data_t a_pipe [0:N-1][0:N-1];
    data_t b_pipe [0:N-1][0:N-1];
    acc_t  c_acc  [0:N-1][0:N-1];

    integer i, j;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (i = 0; i < N; i = i + 1) begin
                for (j = 0; j < N; j = j + 1) begin
                    a_pipe[i][j] <= '0;
                    b_pipe[i][j] <= '0;
                    c_acc[i][j]  <= '0;
                end
            end
        end else begin
            for (i = 0; i < N; i = i + 1) begin
                for (j = 0; j < N; j = j + 1) begin
                    if (i == 0)
                        a_pipe[i][j] <= a_pipe[i][j]; 
                    else
                        a_pipe[i][j] <= a_pipe[i-1][j];
                    if (j == 0)
                        b_pipe[i][j] <= b_pipe[i][j];
                    else
                        b_pipe[i][j] <= b_pipe[i][j-1];
                    c_acc[i][j] <= c_acc[i][j] + a_pipe[i][j] * b_pipe[i][j];
                end
            end
        end
    end
endmodule