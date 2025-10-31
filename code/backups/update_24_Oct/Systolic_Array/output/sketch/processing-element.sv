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