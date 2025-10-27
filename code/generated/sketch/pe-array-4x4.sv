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