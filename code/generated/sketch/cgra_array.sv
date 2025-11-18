module CGRA_Array (
    input  logic clk,
    input  logic rst_n
);
    GPE gpe_inst[0:1][0:3];
    GIB gib_inst[0:1][0:3];
    integer i, j;

    generate
        for (i = 0; i < 2; i = i + 1) begin : gen_row
            for (j = 0; j < 4; j = j + 1) begin : gen_col
                GPE u_gpe (
                    .clk(clk),
                    .rst_n(rst_n)
                );
                GIB u_gib (
                    .clk(clk),
                    .rst_n(rst_n)
                );
            end
        end
    endgenerate
endmodule