module RX_State_Machine (
    input  logic clk,
    input  logic rst_n,
    input  logic rx_serial,
    input  logic baud_tick,
    output logic sample_en,
    output logic rx_done,
    output logic frame_error
);
    typedef enum logic [2:0] {
        IDLE,
        START_BIT,
        DATA_BITS,
        STOP_BIT,
        DONE
    } state_t;

    state_t current_state, next_state;
    logic bit_count_done;
    logic [2:0] bit_count;
    logic bit_count_en;
    logic start_detected;

    Bit_Counter u_bit_counter (
        .clk   (clk),
        .rst_n (rst_n),
        .en    (bit_count_en),
        .done  (bit_count_done),
        .count (bit_count)
    );

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            current_state <= IDLE;
        else
            current_state <= next_state;
    end

    always_comb begin
        next_state = current_state;
        sample_en = 1'b0;
        rx_done = 1'b0;
        frame_error = 1'b0;
        bit_count_en = 1'b0;
        start_detected = 1'b0;

        case (current_state)
            IDLE: begin
                if (!rx_serial)
                    next_state = START_BIT;
            end
            START_BIT: begin
                if (baud_tick) begin
                    if (!rx_serial)
                        next_state = DATA_BITS;
                    else
                        next_state = IDLE;
                end
            end
            DATA_BITS: begin
                bit_count_en = baud_tick;
                sample_en = baud_tick;
                if (bit_count_done)
                    next_state = STOP_BIT;
            end
            STOP_BIT: begin
                if (baud_tick) begin
                    if (rx_serial)
                        next_state = DONE;
                    else begin
                        next_state = DONE;
                        frame_error = 1'b1;
                    end
                end
            end
            DONE: begin
                rx_done = 1'b1;
                if (!baud_tick)
                    next_state = IDLE;
            end
            default: next_state = IDLE;
        endcase
    end
endmodule