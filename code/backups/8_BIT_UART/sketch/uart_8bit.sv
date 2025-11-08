module UART_8bit (
    input  logic        clk,
    input  logic        rst_n,
    input  logic [7:0]  tx_data,
    input  logic        tx_start,
    output logic        tx_busy,
    output logic        tx_serial,
    input  logic        rx_serial,
    output logic [7:0]  rx_data,
    output logic        rx_ready
);
    logic baud_tick;
    logic tx_enable;
    logic rx_enable;
    logic [7:0] status_flags;
    logic parity_error;
    logic frame_error;

    Baud_Rate_Generator u_baud_gen (
        .clk       (clk),
        .rst_n     (rst_n),
        .baud_tick (baud_tick)
    );

    UART_Transmitter u_tx (
        .clk       (clk),
        .rst_n     (rst_n),
        .data_in   (tx_data),
        .start     (tx_start & tx_enable),
        .baud_tick (baud_tick),
        .tx_serial (tx_serial),
        .busy      (tx_busy)
    );

    UART_Receiver u_rx (
        .clk         (clk),
        .rst_n       (rst_n),
        .rx_serial   (rx_serial),
        .baud_tick   (baud_tick),
        .data_out    (rx_data),
        .data_ready  (rx_ready),
        .parity_error(parity_error),
        .frame_error (frame_error)
    );

    UART_Controller u_ctrl (
        .clk         (clk),
        .rst_n       (rst_n),
        .tx_busy     (tx_busy),
        .rx_ready    (rx_ready),
        .tx_enable   (tx_enable),
        .rx_enable   (rx_enable),
        .status_flags(status_flags)
    );
endmodule