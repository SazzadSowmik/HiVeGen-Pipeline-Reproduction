module Clock_Enable_Generator (
    input  logic clk,
    input  logic rst_n,
    input  logic [31:0] baud_en,
    output logic clk_en
);
    logic [31:0] counter;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            counter <= 32'd0;
            clk_en  <= 1'b0;
        end else begin
            if (counter >= baud_en - 1) begin
                counter <= 32'd0;
                clk_en  <= 1'b1;
            end else begin
                counter <= counter + 1;
                clk_en  <= 1'b0;
            end
        end
    end
endmodule