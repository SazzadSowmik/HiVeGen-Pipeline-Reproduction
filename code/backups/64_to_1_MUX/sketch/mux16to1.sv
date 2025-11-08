module mux16to1 (
    input  logic        clk,
    input  logic        rst_n,
    input  logic [15:0][7:0] in,
    input  logic [3:0]  sel,
    output logic [7:0]  out
);
    logic [7:0] out0;
    logic [7:0] out1;
    logic [7:0][7:0] in0;
    logic [7:0][7:0] in1;
    logic [1:0][7:0] in_final;
    integer i;

    always_comb begin
        for (i = 0; i < 8; i = i + 1) begin
            in0[i] = in[i];
            in1[i] = in[i+8];
        end
    end

    mux8to1 u_mux0 (
        .clk(clk),
        .rst_n(rst_n),
        .in(in0),
        .sel(sel[2:0]),
        .out(out0)
    );

    mux8to1 u_mux1 (
        .clk(clk),
        .rst_n(rst_n),
        .in(in1),
        .sel(sel[2:0]),
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
        .sel(sel[3]),
        .out(out)
    );
endmodule