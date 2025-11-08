module Baud_Rate_Generator (
    input  logic clk,
    input  logic rst_n,
    output logic baud_tick
);
    logic baud_en_sig;
    logic [31:0] baud_en_vec;
    logic clk_en_sig;
    integer i;

    Baud_Divider u_baud_div (
        .clk    (clk),
        .rst_n  (rst_n),
        .baud_en(baud_en_sig)
    );

    always_comb begin
        for (i = 0; i < 32; i = i + 1) begin
            baud_en_vec[i] = baud_en_sig;
        end
    end

    Clock_Enable_Generator u_clk_en_gen (
        .clk    (clk),
        .rst_n  (rst_n),
        .baud_en(baud_en_vec),
        .clk_en (clk_en_sig)
    );

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            baud_tick <= 1'b0;
        else
            baud_tick <= clk_en_sig;
    end
endmodule