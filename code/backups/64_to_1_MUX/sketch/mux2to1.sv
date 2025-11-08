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