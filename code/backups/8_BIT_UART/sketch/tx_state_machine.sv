module TX_State_Machine (
    input  logic clk,
    input  logic rst_n,
    input  logic start,
    input  logic baud_tick,
    output logic shift_en,
    output logic load,
    output logic tx_done
);
    typedef enum logic [2:0] {
        IDLE,
        START_BIT,
        DATA_BITS,
        PARITY_BIT,
        STOP_BIT,
        DONE
    } state_t;

    state_t current_state, next_state;
    logic bit_count_done;
    logic [2:0] bit_count;
    logic bit_count_en;

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
        shift_en = 1'b0;
        load = 1'b0;
        tx_done = 1'b0;
        bit_count_en = 1'b0;

        case (current_state)
            IDLE: begin
                if (start)
                    next_state = START_BIT;
            end
            START_BIT: begin
                if (baud_tick)
                    next_state = DATA_BITS;
                load = 1'b1;
            end
            DATA_BITS: begin
                bit_count_en = baud_tick;
                shift_en = baud_tick;
                if (bit_count_done)
                    next_state = PARITY_BIT;
            end
            PARITY_BIT: begin
                if (baud_tick)
                    next_state = STOP_BIT;
            end
            STOP_BIT: begin
                if (baud_tick)
                    next_state = DONE;
            end
            DONE: begin
                tx_done = 1'b1;
                if (!start)
                    next_state = IDLE;
            end
            default: next_state = IDLE;
        endcase
    end
endmodule