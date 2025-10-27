module ClockResetUnit (
    input  logic clk_in,
    input  logic rst_in,
    output logic clk_out,
    output logic rst_n_out
);
    parameter integer DIV_FACTOR = 2;
    parameter integer GATE_ENABLE = 1;

    logic [31:0] div_cnt;
    logic clk_div;
    logic clk_gated;
    logic rst_sync1, rst_sync2;

    always_ff @(posedge clk_in or posedge rst_in) begin
        if (rst_in) begin
            div_cnt <= 32'd0;
            clk_div <= 1'b0;
        end else begin
            if (div_cnt == (DIV_FACTOR/2 - 1)) begin
                clk_div <= ~clk_div;
                div_cnt <= 32'd0;
            end else begin
                div_cnt <= div_cnt + 32'd1;
            end
        end
    end

    always_ff @(posedge clk_div or posedge rst_in) begin
        if (rst_in) begin
            rst_sync1 <= 1'b0;
            rst_sync2 <= 1'b0;
        end else begin
            rst_sync1 <= 1'b1;
            rst_sync2 <= rst_sync1;
        end
    end

    always_comb begin
        if (GATE_ENABLE == 1)
            clk_gated = clk_div & rst_sync2;
        else
            clk_gated = clk_div;
    end

    assign clk_out = clk_gated;
    assign rst_n_out = rst_sync2;

endmodule