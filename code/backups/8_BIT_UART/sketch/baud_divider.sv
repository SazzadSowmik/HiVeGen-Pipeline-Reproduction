module Baud_Divider (
    input  logic clk,
    input  logic rst_n,
    output logic baud_en
);
    logic [31:0] baud_en_vec;
    logic clk_en_int;
    integer i;
    logic [31:0] counter;
    parameter integer DIVISOR = 434;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (i = 0; i < 32; i = i + 1) begin
                baud_en_vec[i] <= 1'b0;
            end
            counter <= 32'd0;
        end else begin
            if (counter >= (DIVISOR - 1)) begin
                counter <= 32'd0;
                for (i = 0; i < 32; i = i + 1) begin
                    baud_en_vec[i] <= 1'b1;
                end
            end else begin
                counter <= counter + 1;
                for (i = 0; i < 32; i = i + 1) begin
                    baud_en_vec[i] <= 1'b0;
                end
            end
        end
    end

    Clock_Enable_Generator u_clk_en_gen (
        .clk    (clk),
        .rst_n  (rst_n),
        .baud_en(baud_en_vec),
        .clk_en (clk_en_int)
    );

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            baud_en <= 1'b0;
        end else begin
            baud_en <= clk_en_int;
        end
    end
endmodule