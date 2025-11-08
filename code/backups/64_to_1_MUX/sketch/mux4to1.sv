module mux4to1 (
    input  logic        clk,
    input  logic        rst_n,
    input  logic [3:0][7:0] in,
    input  logic [1:0]  sel,
    output logic [7:0]  out
);
    logic [7:0] out0;
    logic [7:0] out1;
    logic [1:0][7:0] in0;
    logic [1:0][7:0] in1;
    logic [1:0][7:0] in_final;
    integer i;

    always_comb begin
        for (i = 0; i < 8; i = i + 1) begin
            in0[0][i] = in[0][i];
            in0[1][i] = in[1][i];
            in1[0][i] = in[2][i];
            in1[1][i] = in[3][i];
        end
    end

    mux2to1 u_mux0 (
        .clk(clk),
        .rst_n(rst_n),
        .in0(in0[0+:2]),
        .in1(in0[0+:2]),
        .sel(sel[0]),
        .out(out0)
    );

    mux2to1 u_mux1 (
        .clk(clk),
        .rst_n(rst_n),
        .in0(in1[0+:2]),
        .in1(in1[0+:2]),
        .sel(sel[0]),
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
        .in0(in_final[0+:2]),
        .in1(in_final[0+:2]),
        .sel(sel[1]),
        .out(out)
    );
endmodule