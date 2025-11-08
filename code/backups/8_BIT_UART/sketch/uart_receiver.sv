module UART_Receiver (
    input  logic clk,
    input  logic rst_n,
    input  logic rx_serial,
    input  logic baud_tick,
    output logic [7:0] data_out,
    output logic data_ready,
    output logic parity_error,
    output logic frame_error
);
    logic sample_en;
    logic rx_done;
    logic [7:0] rx_data;
    logic parity_bit_internal;
    logic parity_error_internal;
    logic parity_mode;
    integer i;

    assign parity_mode = 1'b0;

    RX_State_Machine u_rx_sm (
        .clk         (clk),
        .rst_n       (rst_n),
        .rx_serial   (rx_serial),
        .baud_tick   (baud_tick),
        .sample_en   (sample_en),
        .rx_done     (rx_done),
        .frame_error (frame_error)
    );

    RX_Shift_Register u_rx_shift (
        .clk        (clk),
        .rst_n      (rst_n),
        .sample_en  (sample_en),
        .serial_in  (rx_serial),
        .data_out   (rx_data),
        .done       ()
    );

    Parity_Generator_Checker u_parity_chk (
        .data         (rx_data),
        .parity_mode  (parity_mode),
        .check_en     (rx_done),
        .parity_bit   (parity_bit_internal),
        .parity_error (parity_error_internal)
    );

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            data_ready <= 1'b0;
            parity_error <= 1'b0;
            for (i = 0; i < 8; i = i + 1) begin
                data_out[i] <= 1'b0;
            end
        end else begin
            if (rx_done) begin
                data_ready <= 1'b1;
                parity_error <= parity_error_internal;
                for (i = 0; i < 8; i = i + 1) begin
                    data_out[i] <= rx_data[i];
                end
            end else begin
                data_ready <= 1'b0;
            end
        end
    end
endmodule