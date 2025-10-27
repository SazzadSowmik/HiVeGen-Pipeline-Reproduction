module InputBufferB (
    input  logic clk,
    input  logic rst_n
);
    parameter COLS = 4;
    parameter ROWS = 64;
    parameter DATA_WIDTH = 16;

    logic [DATA_WIDTH-1:0] line_buffer [0:COLS-1][0:ROWS-1];
    logic [5:0] write_ptr [0:COLS-1];
    logic [5:0] read_ptr  [0:COLS-1];
    logic [DATA_WIDTH-1:0] input_data [0:COLS-1];
    logic [DATA_WIDTH-1:0] output_data [0:COLS-1];
    logic load_enable;
    logic stream_enable;

    typedef enum logic [1:0] {
        IDLE,
        LOAD,
        STREAM
    } state_t;

    state_t state, next_state;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            state <= IDLE;
        else
            state <= next_state;
    end

    always_comb begin
        next_state = state;
        load_enable = 1'b0;
        stream_enable = 1'b0;
        case (state)
            IDLE: begin
                next_state = LOAD;
            end
            LOAD: begin
                load_enable = 1'b1;
                if (&write_ptr[0])
                    next_state = STREAM;
            end
            STREAM: begin
                stream_enable = 1'b1;
                if (&read_ptr[0])
                    next_state = IDLE;
            end
        endcase
    end

    integer i, j;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (i = 0; i < COLS; i = i + 1) begin
                write_ptr[i] <= 0;
                read_ptr[i] <= 0;
                for (j = 0; j < ROWS; j = j + 1) begin
                    line_buffer[i][j] <= '0;
                end
            end
        end else begin
            if (load_enable) begin
                for (i = 0; i < COLS; i = i + 1) begin
                    line_buffer[i][write_ptr[i]] <= input_data[i];
                    if (write_ptr[i] < ROWS-1)
                        write_ptr[i] <= write_ptr[i] + 1;
                    else
                        write_ptr[i] <= 0;
                end
            end else if (stream_enable) begin
                for (i = 0; i < COLS; i = i + 1) begin
                    output_data[i] <= line_buffer[i][read_ptr[i]];
                    if (read_ptr[i] < ROWS-1)
                        read_ptr[i] <= read_ptr[i] + 1;
                    else
                        read_ptr[i] <= 0;
                end
            end
        end
    end

endmodule