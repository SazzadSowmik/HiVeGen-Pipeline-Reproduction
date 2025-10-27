module SystolicPEArray_4x4 (
    input  logic clk,
    input  logic rst_n
);
    parameter DATA_WIDTH = 16;

    logic signed [DATA_WIDTH-1:0] a_in [0:3][0:3];
    logic signed [DATA_WIDTH-1:0] b_in [0:3][0:3];
    logic signed [2*DATA_WIDTH-1:0] psum_in [0:3][0:3];
    logic signed [DATA_WIDTH-1:0] a_out [0:3][0:3];
    logic signed [DATA_WIDTH-1:0] b_out [0:3][0:3];
    logic signed [2*DATA_WIDTH-1:0] psum_out [0:3][0:3];

    genvar i, j;
    generate
        for (i = 0; i < 4; i = i + 1) begin : row_gen
            for (j = 0; j < 4; j = j + 1) begin : col_gen
                ProcessingElement pe_inst (
                    .clk(clk),
                    .rst_n(rst_n)
                );
            end
        end
    endgenerate

    logic signed [DATA_WIDTH-1:0] a_pipe [0:4][0:3];
    logic signed [DATA_WIDTH-1:0] b_pipe [0:3][0:4];
    logic signed [2*DATA_WIDTH-1:0] psum_pipe [0:4][0:4];

    integer x, y;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (x = 0; x < 5; x = x + 1) begin
                for (y = 0; y < 4; y = y + 1) begin
                    a_pipe[x][y] <= '0;
                end
            end
            for (x = 0; x < 4; x = x + 1) begin
                for (y = 0; y < 5; y = y + 1) begin
                    b_pipe[x][y] <= '0;
                end
            end
            for (x = 0; x < 5; x = x + 1) begin
                for (y = 0; y < 5; y = y + 1) begin
                    psum_pipe[x][y] <= '0;
                end
            end
        end else begin
            for (x = 0; x < 4; x = x + 1) begin
                for (y = 0; y < 4; y = y + 1) begin
                    a_pipe[x+1][y] <= a_pipe[x][y];
                    b_pipe[x][y+1] <= b_pipe[x][y];
                    psum_pipe[x+1][y+1] <= psum_pipe[x][y] + a_pipe[x][y] * b_pipe[x][y];
                end
            end
        end
    end
endmodule