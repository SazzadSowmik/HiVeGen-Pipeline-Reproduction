module Bit_Counter (
    input  logic clk,
    input  logic rst_n,
    input  logic en,
    output logic done,
    output logic [2:0] count
);
    integer i;
    logic [2:0] count_reg;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (i = 0; i < 3; i = i + 1) begin
                count_reg[i] <= 1'b0;
            end
        end else if (en) begin
            if (count_reg == 3'd7) begin
                for (i = 0; i < 3; i = i + 1) begin
                    count_reg[i] <= 1'b0;
                end
            end else begin
                count_reg <= count_reg + 3'd1;
            end
        end
    end

    always_comb begin
        done = (count_reg == 3'd7);
    end

    for (i = 0; i < 3; i = i + 1) begin
        assign count[i] = count_reg[i];
    end
endmodule