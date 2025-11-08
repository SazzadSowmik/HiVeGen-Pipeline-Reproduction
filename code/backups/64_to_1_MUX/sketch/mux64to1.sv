module mux64to1 (
    input  logic        clk,
    input  logic        rst_n,
    input  logic [63:0][7:0] in,
    input  logic [5:0]  sel,
    output logic [7:0]  out
);
    logic [7:0] out0;
    logic [7:0] out1;
    logic [31:0][7:0] in0;
    logic [31:0][7:0] in1;
    logic [1:0][7:0] in_final;
    integer i;

    always_comb begin
        for (i = 0; i < 32; i = i + 1) begin
            in0[i] = in[i];
            in1[i] = in[i + 32];
        end
    end

    mux32to1 u_mux0 (
        .clk(clk),
        .rst_n(rst_n),
        .in(in0),
        .sel(sel[4:0]),
        .out(out0)
    );

    mux32to1 u_mux1 (
        .clk(clk),
        .rst_n(rst_n),
        .in(in1),
        .sel(sel[4:0]),
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
        .sel(sel[5]),
        .out(out)
    );
endmodule