module Scratchpad_Memory_System (
    input  logic clk,
    input  logic rst_n
);
    genvar i;
    generate
        for (i = 0; i < 8; i = i + 1) begin : BANKS
            Scratchpad_Bank bank_inst (
                .clk   (clk),
                .rst_n (rst_n)
            );
        end
    endgenerate
endmodule