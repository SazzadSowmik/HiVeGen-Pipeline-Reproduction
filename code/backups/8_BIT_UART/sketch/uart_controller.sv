module UART_Controller (
    input  logic        clk,
    input  logic        rst_n,
    input  logic        tx_busy,
    input  logic        rx_ready,
    output logic        tx_enable,
    output logic        rx_enable,
    output logic [7:0]  status_flags
);
    logic [7:0] status_next;
    integer i;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (i = 0; i < 8; i = i + 1) begin
                status_flags[i] <= 1'b0;
            end
            tx_enable <= 1'b0;
            rx_enable <= 1'b0;
        end else begin
            tx_enable <= ~tx_busy;
            rx_enable <= rx_ready;
            status_next[0] = tx_busy;
            status_next[1] = rx_ready;
            status_next[2] = tx_enable;
            status_next[3] = rx_enable;
            for (i = 4; i < 8; i = i + 1) begin
                status_next[i] = 1'b0;
            end
            for (i = 0; i < 8; i = i + 1) begin
                status_flags[i] <= status_next[i];
            end
        end
    end
endmodule