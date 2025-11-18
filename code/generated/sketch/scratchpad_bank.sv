module Scratchpad_Bank (
    input  logic clk,
    input  logic rst_n
);
    logic [31:0] mem [0:2047];
    logic [31:0] rdata;
    logic [31:0] wdata;
    logic [10:0] addr;
    logic        we;

    integer i;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (i = 0; i < 2048; i = i + 1) begin
                mem[i] <= 32'd0;
            end
        end else begin
            if (we) begin
                mem[addr] <= wdata;
            end
        end
    end

    always_ff @(posedge clk) begin
        rdata <= mem[addr];
    end
endmodule