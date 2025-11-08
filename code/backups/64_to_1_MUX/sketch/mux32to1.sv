module mux32to1 (
    input  logic        clk,
    input  logic        rst_n,
    input  logic [31:0][7:0] in,
    input  logic [4:0]  sel,
    output logic [7:0]  out
);
    logic [7:0] out0;
    logic [7:0] out1;
    logic [15:0][7:0] in0;
    logic [15:0][7:0] in1;
    logic [1:0][7:0] in_final;
    integer i, j;

    always_comb begin
        for (i = 0; i < 16; i = i + 1) begin
            for (j = 0; j < 8; j = j + 1) begin
                in0[i][j] = in[i][j];
                in1[i][j] = in[i+16][j];
            end
        end
    end

    mux16to1 u_mux0 (
        .clk(clk),
        .rst_n(rst_n),
        .in(in0),
        .sel(sel[3:0]),
        .out(out0)
    );

    mux16to1 u_mux1 (
        .clk(clk),
        .rst_n(rst_n),
        .in(in1),
        .sel(sel[3:0]),
        .out(out1)
    );

    always_comb begin
        for (j = 0; j < 8; j = j + 1) begin
            in_final[0][j] = out0[j];
            in_final[1][j] = out1[j];
        end
    end

    mux2to1 u_mux2 (
        .clk(clk),
        .rst_n(rst_n),
        .in(in_final),
        .sel(sel[4]),
        .out(out)
    );
endmodule