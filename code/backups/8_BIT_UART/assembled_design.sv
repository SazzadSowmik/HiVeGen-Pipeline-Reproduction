
// ---- Bit_Counter ----
module Bit_Counter (
    input  logic clk,
    input  logic rst_n,
    input  logic en,
    output logic done,
    output logic [2:0] count
);
    integer i;
    logic [2:0] count_reg;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (i = 0; i < 3; i = i + 1) begin
                count_reg[i] <= 1'b0;
            end
        end else if (en) begin
            if (count_reg == 3'd7) begin
                for (i = 0; i < 3; i = i + 1) begin
                    count_reg[i] <= 1'b0;
                end
            end else begin
                count_reg <= count_reg + 3'd1;
            end
        end
    end

    always_comb begin
        done = (count_reg == 3'd7);
    end

    for (i = 0; i < 3; i = i + 1) begin
        assign count[i] = count_reg[i];
    end
endmodule

// ---- TX_Shift_Register ----
module TX_Shift_Register (
    input  logic        clk,
    input  logic        rst_n,
    input  logic        load,
    input  logic        shift_en,
    input  logic [7:0]  data_in,
    output logic        serial_out,
    output logic        done
);
    logic [7:0] shift_reg;
    logic [2:0] bit_count;
    logic       bit_done;
    integer i;

    Bit_Counter u_bit_counter (
        .clk   (clk),
        .rst_n (rst_n),
        .en    (shift_en),
        .done  (bit_done),
        .count (bit_count)
    );

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (i = 0; i < 8; i = i + 1) begin
                shift_reg[i] <= 1'b0;
            end
        end else if (load) begin
            for (i = 0; i < 8; i = i + 1) begin
                shift_reg[i] <= data_in[i];
            end
        end else if (shift_en) begin
            for (i = 0; i < 7; i = i + 1) begin
                shift_reg[i] <= shift_reg[i+1];
            end
            shift_reg[7] <= 1'b0;
        end
    end

    assign serial_out = shift_reg[0];
    assign done = bit_done;
endmodule

// ---- TX_State_Machine ----
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

// ---- Parity_Generator_Checker ----
module Parity_Generator_Checker (
    input  logic [7:0] data,
    input  logic parity_mode, 
    input  logic check_en,
    output logic parity_bit,
    output logic parity_error
);
    integer i;
    logic parity_calc;
    logic parity_expected;

    always_comb begin
        parity_calc = 1'b0;
        for (i = 0; i < 8; i = i + 1) begin
            parity_calc = parity_calc ^ data[i];
        end
        if (parity_mode == 1'b0) begin
            parity_bit = parity_calc;
        end else begin
            parity_bit = ~parity_calc;
        end
    end

    always_comb begin
        parity_error = 1'b0;
        if (check_en) begin
            parity_expected = 1'b0;
            for (i = 0; i < 8; i = i + 1) begin
                parity_expected = parity_expected ^ data[i];
            end
            if (parity_mode == 1'b1) begin
                parity_expected = ~parity_expected;
            end
            if (parity_expected != parity_bit) begin
                parity_error = 1'b1;
            end
        end
    end
endmodule

// ---- UART_Transmitter ----
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

// ---- RX_Shift_Register ----
module RX_Shift_Register (
    input  logic clk,
    input  logic rst_n,
    input  logic sample_en,
    input  logic serial_in,
    output logic [7:0] data_out,
    output logic done
);
    logic [7:0] shift_reg;
    logic [2:0] bit_count;
    logic bit_done;
    integer i;

    Bit_Counter bit_counter_inst (
        .clk(clk),
        .rst_n(rst_n),
        .en(sample_en),
        .done(bit_done),
        .count(bit_count)
    );

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (i = 0; i < 8; i = i + 1) begin
                shift_reg[i] <= 1'b0;
            end
        end else if (sample_en) begin
            for (i = 7; i > 0; i = i - 1) begin
                shift_reg[i] <= shift_reg[i-1];
            end
            shift_reg[0] <= serial_in;
        end
    end

    assign data_out = shift_reg;
    assign done = bit_done;
endmodule

// ---- RX_State_Machine ----
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

// ---- UART_Receiver ----
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

// ---- Clock_Enable_Generator ----
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

// ---- Baud_Divider ----
module Baud_Divider (
    input  logic clk,
    input  logic rst_n,
    output logic baud_en
);
    logic [31:0] baud_en_vec;
    logic clk_en_int;
    integer i;
    logic [31:0] counter;
    parameter integer DIVISOR = 434;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (i = 0; i < 32; i = i + 1) begin
                baud_en_vec[i] <= 1'b0;
            end
            counter <= 32'd0;
        end else begin
            if (counter >= (DIVISOR - 1)) begin
                counter <= 32'd0;
                for (i = 0; i < 32; i = i + 1) begin
                    baud_en_vec[i] <= 1'b1;
                end
            end else begin
                counter <= counter + 1;
                for (i = 0; i < 32; i = i + 1) begin
                    baud_en_vec[i] <= 1'b0;
                end
            end
        end
    end

    Clock_Enable_Generator u_clk_en_gen (
        .clk    (clk),
        .rst_n  (rst_n),
        .baud_en(baud_en_vec),
        .clk_en (clk_en_int)
    );

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            baud_en <= 1'b0;
        end else begin
            baud_en <= clk_en_int;
        end
    end
endmodule

// ---- Baud_Rate_Generator ----
module Baud_Rate_Generator (
    input  logic clk,
    input  logic rst_n,
    output logic baud_tick
);
    logic baud_en_sig;
    logic [31:0] baud_en_vec;
    logic clk_en_sig;
    integer i;

    Baud_Divider u_baud_div (
        .clk    (clk),
        .rst_n  (rst_n),
        .baud_en(baud_en_sig)
    );

    always_comb begin
        for (i = 0; i < 32; i = i + 1) begin
            baud_en_vec[i] = baud_en_sig;
        end
    end

    Clock_Enable_Generator u_clk_en_gen (
        .clk    (clk),
        .rst_n  (rst_n),
        .baud_en(baud_en_vec),
        .clk_en (clk_en_sig)
    );

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            baud_tick <= 1'b0;
        else
            baud_tick <= clk_en_sig;
    end
endmodule

// ---- UART_Controller ----
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

// ---- UART_8bit ----
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
