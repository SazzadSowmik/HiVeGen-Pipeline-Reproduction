
// ---- mux2to1 ----
module mux2to1 (
    input  logic        clk,
    input  logic        rst_n,
    input  logic [1:0][7:0] in0,
    input  logic [1:0][7:0] in1,
    input  logic        sel,
    output logic [7:0]  out
);
    integer i;
    logic [7:0] selected_in0;
    logic [7:0] selected_in1;

    always_comb begin
        for (i = 0; i < 8; i = i + 1) begin
            selected_in0[i] = in0[sel][i];
            selected_in1[i] = in1[sel][i];
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            out <= '0;
        else
            out <= (sel) ? selected_in1 : selected_in0;
    end
endmodule

// ---- mux4to1 ----
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

// ---- mux8to1 ----
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

// ---- mux16to1 ----
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

// ---- mux32to1 ----
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

// ---- mux64to1 ----
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
