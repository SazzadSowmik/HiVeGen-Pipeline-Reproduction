module mux8to1 (
    input  logic        clk,
    input  logic        rst_n,
    input  logic [7:0][7:0] in,
    input  logic [2:0]  sel,
    output logic [7:0]  out
);
    logic [7:0] out0;
    logic [7:0] out1;
    logic [3:0][7:0] in0;
    logic [3:0][7:0] in1;
    logic [1:0][7:0] in_final;
    integer i;

    always_comb begin
        for (i = 0; i < 8; i = i + 1) begin
            in0[0][i] = in[0][i];
            in0[1][i] = in[1][i];
            in0[2][i] = in[2][i];
            in0[3][i] = in[3][i];
            in1[0][i] = in[4][i];
            in1[1][i] = in[5][i];
            in1[2][i] = in[6][i];
            in1[3][i] = in[7][i];
        end
    end

    mux4to1 u_mux0 (
        .clk(clk),
        .rst_n(rst_n),
        .in(in0),
        .sel(sel[1:0]),
        .out(out0)
    );

    mux4to1 u_mux1 (
        .clk(clk),
        .rst_n(rst_n),
        .in(in1),
        .sel(sel[1:0]),
        .out(out1)
    );

    always_comb begin
        for (i = 0; i < 8; i = i + 1) begin
            in_final[0][i] = out0[i];
            in_final[1][i] = out1[i];
        end
    end

    mux2to1 u_mux2 (
        .clk(clk),
        .rst_n(rst_n),
        .in(in_final),
        .sel(sel[2]),
        .out(out)
    );
endmodule