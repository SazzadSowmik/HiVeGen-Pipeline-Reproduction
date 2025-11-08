module UART_Transmitter (
    input  logic        clk,
    input  logic        rst_n,
    input  logic [7:0]  data_in,
    input  logic        start,
    input  logic        baud_tick,
    output logic        tx_serial,
    output logic        busy
);
    logic shift_en;
    logic load;
    logic tx_done;
    logic serial_out;
    logic parity_bit;
    logic parity_error;
    logic [7:0] data_buf;
    integer i;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (i = 0; i < 8; i = i + 1) begin
                data_buf[i] <= 1'b0;
            end
        end else if (load) begin
            for (i = 0; i < 8; i = i + 1) begin
                data_buf[i] <= data_in[i];
            end
        end
    end

    TX_State_Machine u_tx_sm (
        .clk       (clk),
        .rst_n     (rst_n),
        .start     (start),
        .baud_tick (baud_tick),
        .shift_en  (shift_en),
        .load      (load),
        .tx_done   (tx_done)
    );

    TX_Shift_Register u_tx_shift (
        .clk        (clk),
        .rst_n      (rst_n),
        .load       (load),
        .shift_en   (shift_en),
        .data_in    (data_buf),
        .serial_out (serial_out),
        .done       ()
    );

    Parity_Generator_Checker u_parity_gen (
        .data         (data_buf),
        .parity_mode  (1'b0),
        .check_en     (1'b0),
        .parity_bit   (parity_bit),
        .parity_error (parity_error)
    );

    typedef enum logic [2:0] {
        IDLE,
        START_BIT,
        DATA_BITS,
        PARITY_BIT,
        STOP_BIT
    } tx_state_t;

    tx_state_t state, next_state;
    logic [2:0] bit_cnt;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
            bit_cnt <= 3'd0;
        end else if (baud_tick) begin
            state <= next_state;
            if (state == DATA_BITS && shift_en)
                bit_cnt <= bit_cnt + 3'd1;
            else if (state != DATA_BITS)
                bit_cnt <= 3'd0;
        end
    end

    always_comb begin
        next_state = state;
        case (state)
            IDLE: if (start) next_state = START_BIT;
            START_BIT: if (baud_tick) next_state = DATA_BITS;
            DATA_BITS: if (bit_cnt == 3'd7 && baud_tick) next_state = PARITY_BIT;
            PARITY_BIT: if (baud_tick) next_state = STOP_BIT;
            STOP_BIT: if (baud_tick) next_state = IDLE;
            default: next_state = IDLE;
        endcase
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            tx_serial <= 1'b1;
            busy <= 1'b0;
        end else if (baud_tick) begin
            case (state)
                IDLE: begin
                    tx_serial <= 1'b1;
                    busy <= 1'b0;
                end
                START_BIT: begin
                    tx_serial <= 1'b0;
                    busy <= 1'b1;
                end
                DATA_BITS: begin
                    tx_serial <= serial_out;
                    busy <= 1'b1;
                end
                PARITY_BIT: begin
                    tx_serial <= parity_bit;
                    busy <= 1'b1;
                end
                STOP_BIT: begin
                    tx_serial <= 1'b1;
                    busy <= 1'b1;
                end
                default: begin
                    tx_serial <= 1'b1;
                    busy <= 1'b0;
                end
            endcase
        end
    end
endmodule