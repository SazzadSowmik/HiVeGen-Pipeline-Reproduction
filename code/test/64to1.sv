
// ---- mux2to1 ----
module mux2to1 (
    input  logic [7:0] a,
    input  logic [7:0] b,
    input  logic       sel,
    output logic [7:0] y
);
    always_comb begin
        for (int i = 0; i < 8; i = i + 1) begin
            if (sel == 1'b0)
                y[i] = a[i];
            else
                y[i] = b[i];
        end
    end
endmodule

// ---- mux4to1_stage ----
module mux4to1_stage (
    input  logic        clk,
    input  logic        rst_n,
    input  logic [3:0][7:0] din,
    input  logic [1:0]  sel,
    output logic [7:0]  dout
);
    logic [7:0] y0;
    logic [7:0] y1;
    logic [7:0] y_final;
    logic [7:0] in0_a;
    logic [7:0] in0_b;
    logic [7:0] in1_a;
    logic [7:0] in1_b;
    logic [7:0] final_a;
    logic [7:0] final_b;

    always_comb begin
        for (int i = 0; i < 8; i = i + 1) begin
            in0_a[i] = din[0][i];
            in0_b[i] = din[1][i];
            in1_a[i] = din[2][i];
            in1_b[i] = din[3][i];
        end
    end

    mux2to1 u_mux0 (
        .a(in0_a),
        .b(in0_b),
        .sel(sel[0]),
        .y(y0)
    );

    mux2to1 u_mux1 (
        .a(in1_a),
        .b(in1_b),
        .sel(sel[0]),
        .y(y1)
    );

    always_comb begin
        for (i = 0; i < 8; i = i + 1) begin
            final_a[i] = y0[i];
            final_b[i] = y1[i];
        end
    end

    mux2to1 u_mux2 (
        .a(final_a),
        .b(final_b),
        .sel(sel[1]),
        .y(y_final)
    );

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            dout <= 8'b0;
        else
            dout <= y_final;
    end
endmodule

// ---- mux8to1_stage ----
module mux8to1_stage (
    input  logic        clk,
    input  logic        rst_n,
    input  logic [7:0][7:0] din,
    input  logic [2:0]  sel,
    output logic [7:0]  dout
);
    logic [3:0][7:0] din_low;
    logic [3:0][7:0] din_high;
    logic [7:0] dout_low;
    logic [7:0] dout_high;

    always_comb begin
        for (int i = 0; i < 8; i = i + 1) begin
            din_low[0][i] = din[0][i];
            din_low[1][i] = din[1][i];
            din_low[2][i] = din[2][i];
            din_low[3][i] = din[3][i];
            din_high[0][i] = din[4][i];
            din_high[1][i] = din[5][i];
            din_high[2][i] = din[6][i];
            din_high[3][i] = din[7][i];
        end
    end

    mux4to1_stage u_mux_low (
        .clk(clk),
        .rst_n(rst_n),
        .din(din_low),
        .sel(sel[1:0]),
        .dout(dout_low)
    );

    mux4to1_stage u_mux_high (
        .clk(clk),
        .rst_n(rst_n),
        .din(din_high),
        .sel(sel[1:0]),
        .dout(dout_high)
    );

    mux2to1 u_mux_final (
        .a(dout_low),
        .b(dout_high),
        .sel(sel[2]),
        .y(dout)
    );
endmodule

// ---- pipeline_register ----
module pipeline_register (
    input  logic        clk,
    input  logic        rst_n,
    input  logic [15:0][7:0] d,
    output logic [15:0][7:0] q
);
    integer i, j;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (i = 0; i < 16; i = i + 1) begin
                for (j = 0; j < 8; j = j + 1) begin
                    q[i][j] <= 1'b0;
                end
            end
        end else begin
            for (i = 0; i < 16; i = i + 1) begin
                for (j = 0; j < 8; j = j + 1) begin
                    q[i][j] <= d[i][j];
                end
            end
        end
    end
endmodule

// ---- mux16to1_stage ----
module mux16to1_stage (
    input  logic        clk,
    input  logic        rst_n,
    input  logic [15:0][7:0] din,
    input  logic [3:0]  sel,
    output logic [7:0]  dout
);
    logic [15:0][7:0] din_reg;
    logic [7:0][7:0] din_low;
    logic [7:0][7:0] din_high;
    logic [7:0] dout_low;
    logic [7:0] dout_high;
    integer i, j;

    pipeline_register u_pipe (
        .clk(clk),
        .rst_n(rst_n),
        .d(din),
        .q(din_reg)
    );

    always_comb begin
        for (i = 0; i < 8; i = i + 1) begin
            for (j = 0; j < 8; j = j + 1) begin
                din_low[i][j]  = din_reg[i][j];
                din_high[i][j] = din_reg[i+8][j];
            end
        end
    end

    mux8to1_stage u_mux_low (
        .clk(clk),
        .rst_n(rst_n),
        .din(din_low),
        .sel(sel[2:0]),
        .dout(dout_low)
    );

    mux8to1_stage u_mux_high (
        .clk(clk),
        .rst_n(rst_n),
        .din(din_high),
        .sel(sel[2:0]),
        .dout(dout_high)
    );

    mux2to1 u_mux_final (
        .a(dout_low),
        .b(dout_high),
        .sel(sel[3]),
        .y(dout)
    );
endmodule

// ---- mux32to1_stage ----
module mux32to1_stage (
    input  logic        clk,
    input  logic        rst_n,
    input  logic [31:0][7:0] din,
    input  logic [4:0]  sel,
    output logic [7:0]  dout
);
    logic [15:0][7:0] din_low;
    logic [15:0][7:0] din_high;
    logic [7:0] dout_low;
    logic [7:0] dout_high;
    logic [15:0][7:0] din_low_reg;
    logic [15:0][7:0] din_high_reg;
    integer i, j;

    always_comb begin
        for (i = 0; i < 16; i = i + 1) begin
            for (j = 0; j < 8; j = j + 1) begin
                din_low[i][j] = din[i][j];
                din_high[i][j] = din[i+16][j];
            end
        end
    end

    pipeline_register u_pipe_low (
        .clk(clk),
        .rst_n(rst_n),
        .d(din_low),
        .q(din_low_reg)
    );

    pipeline_register u_pipe_high (
        .clk(clk),
        .rst_n(rst_n),
        .d(din_high),
        .q(din_high_reg)
    );

    mux16to1_stage u_mux_low (
        .clk(clk),
        .rst_n(rst_n),
        .din(din_low_reg),
        .sel(sel[3:0]),
        .dout(dout_low)
    );

    mux16to1_stage u_mux_high (
        .clk(clk),
        .rst_n(rst_n),
        .din(din_high_reg),
        .sel(sel[3:0]),
        .dout(dout_high)
    );

    mux2to1 u_mux_final (
        .a(dout_low),
        .b(dout_high),
        .sel(sel[4]),
        .y(dout)
    );
endmodule

// ---- mux64to1_stage ----
module mux64to1_stage (
    input  logic        clk,
    input  logic        rst_n,
    input  logic [63:0][7:0] din,
    input  logic [5:0]  sel,
    output logic [7:0]  dout
);
    logic [31:0][7:0] din_low;
    logic [31:0][7:0] din_high;
    logic [7:0] dout_low;
    logic [7:0] dout_high;
    logic [15:0][7:0] pipe_in;
    logic [15:0][7:0] pipe_out;
    integer i, j;

    always_comb begin
        for (i = 0; i < 32; i = i + 1) begin
            for (j = 0; j < 8; j = j + 1) begin
                din_low[i][j]  = din[i][j];
                din_high[i][j] = din[i+32][j];
            end
        end
    end

    mux32to1_stage u_mux_low (
        .clk(clk),
        .rst_n(rst_n),
        .din(din_low),
        .sel(sel[4:0]),
        .dout(dout_low)
    );

    mux32to1_stage u_mux_high (
        .clk(clk),
        .rst_n(rst_n),
        .din(din_high),
        .sel(sel[4:0]),
        .dout(dout_high)
    );

    always_comb begin
        for (i = 0; i < 8; i = i + 1) begin
            pipe_in[0][i]  = dout_low[i];
            pipe_in[1][i]  = dout_high[i];
        end
        for (i = 2; i < 16; i = i + 1) begin
            for (j = 0; j < 8; j = j + 1) begin
                pipe_in[i][j] = 1'b0;
            end
        end
    end

    pipeline_register u_pipe (
        .clk(clk),
        .rst_n(rst_n),
        .d(pipe_in),
        .q(pipe_out)
    );

    always_comb begin
        if (sel[5] == 1'b0)
            dout = pipe_out[0];
        else
            dout = pipe_out[1];
    end
endmodule

// ---- mux64to1_pipelined ----
module mux64to1_pipelined (
    input  logic        clk,
    input  logic        rst_n,
    input  logic [63:0][7:0] din,
    input  logic [5:0]  sel,
    output logic [7:0]  dout
);
    logic [7:0] stage_dout;

    mux64to1_stage u_stage (
        .clk(clk),
        .rst_n(rst_n),
        .din(din),
        .sel(sel),
        .dout(stage_dout)
    );

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            dout <= '0;
        else
            dout <= stage_dout;
    end
endmodule
