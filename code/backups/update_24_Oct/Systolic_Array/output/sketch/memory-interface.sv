module MemoryInterface (
    input  logic clk,
    input  logic rst_n
);
    parameter ROWS = 4;
    parameter COLS = 64;
    parameter DATA_WIDTH = 16;

    logic [DATA_WIDTH-1:0] bufferA [0:ROWS-1][0:COLS-1];
    logic [DATA_WIDTH-1:0] bufferB [0:ROWS-1][0:COLS-1];
    logic [DATA_WIDTH-1:0] bufferC [0:ROWS-1][0:COLS-1];

    logic [5:0] write_ptrA [0:ROWS-1];
    logic [5:0] read_ptrA  [0:ROWS-1];
    logic [5:0] write_ptrB [0:ROWS-1];
    logic [5:0] read_ptrB  [0:ROWS-1];
    logic [5:0] write_ptrC [0:ROWS-1];
    logic [5:0] read_ptrC  [0:ROWS-1];

    logic [DATA_WIDTH-1:0] input_dataA [0:ROWS-1];
    logic [DATA_WIDTH-1:0] input_dataB [0:ROWS-1];
    logic [DATA_WIDTH-1:0] input_dataC [0:ROWS-1];
    logic [DATA_WIDTH-1:0] output_dataA [0:ROWS-1];
    logic [DATA_WIDTH-1:0] output_dataB [0:ROWS-1];
    logic [DATA_WIDTH-1:0] output_dataC [0:ROWS-1];

    logic load_enableA, load_enableB, load_enableC;
    logic stream_enableA, stream_enableB, stream_enableC;

    typedef enum logic [1:0] {
        IDLE,
        LOAD,
        STREAM
    } state_t;

    state_t stateA, next_stateA;
    state_t stateB, next_stateB;
    state_t stateC, next_stateC;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            stateA <= IDLE;
            stateB <= IDLE;
            stateC <= IDLE;
        end else begin
            stateA <= next_stateA;
            stateB <= next_stateB;
            stateC <= next_stateC;
        end
    end

    always_comb begin
        next_stateA = stateA;
        next_stateB = stateB;
        next_stateC = stateC;
        load_enableA = 1'b0;
        load_enableB = 1'b0;
        load_enableC = 1'b0;
        stream_enableA = 1'b0;
        stream_enableB = 1'b0;
        stream_enableC = 1'b0;

        case (stateA)
            IDLE: next_stateA = LOAD;
            LOAD: begin
                load_enableA = 1'b1;
                if (&write_ptrA[0]) next_stateA = STREAM;
            end
            STREAM: begin
                stream_enableA = 1'b1;
                if (&read_ptrA[0]) next_stateA = IDLE;
            end
        endcase

        case (stateB)
            IDLE: next_stateB = LOAD;
            LOAD: begin
                load_enableB = 1'b1;
                if (&write_ptrB[0]) next_stateB = STREAM;
            end
            STREAM: begin
                stream_enableB = 1'b1;
                if (&read_ptrB[0]) next_stateB = IDLE;
            end
        endcase

        case (stateC)
            IDLE: next_stateC = LOAD;
            LOAD: begin
                load_enableC = 1'b1;
                if (&write_ptrC[0]) next_stateC = STREAM;
            end
            STREAM: begin
                stream_enableC = 1'b1;
                if (&read_ptrC[0]) next_stateC = IDLE;
            end
        endcase
    end

    integer i, j;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (i = 0; i < ROWS; i = i + 1) begin
                write_ptrA[i] <= 0;
                read_ptrA[i] <= 0;
                write_ptrB[i] <= 0;
                read_ptrB[i] <= 0;
                write_ptrC[i] <= 0;
                read_ptrC[i] <= 0;
                for (j = 0; j < COLS; j = j + 1) begin
                    bufferA[i][j] <= '0;
                    bufferB[i][j] <= '0;
                    bufferC[i][j] <= '0;
                end
            end
        end else begin
            if (load_enableA) begin
                for (i = 0; i < ROWS; i = i + 1) begin
                    bufferA[i][write_ptrA[i]] <= input_dataA[i];
                    if (write_ptrA[i] < COLS-1)
                        write_ptrA[i] <= write_ptrA[i] + 1;
                    else
                        write_ptrA[i] <= 0;
                end
            end else if (stream_enableA) begin
                for (i = 0; i < ROWS; i = i + 1) begin
                    output_dataA[i] <= bufferA[i][read_ptrA[i]];
                    if (read_ptrA[i] < COLS-1)
                        read_ptrA[i] <= read_ptrA[i] + 1;
                    else
                        read_ptrA[i] <= 0;
                end
            end

            if (load_enableB) begin
                for (i = 0; i < ROWS; i = i + 1) begin
                    bufferB[i][write_ptrB[i]] <= input_dataB[i];
                    if (write_ptrB[i] < COLS-1)
                        write_ptrB[i] <= write_ptrB[i] + 1;
                    else
                        write_ptrB[i] <= 0;
                end
            end else if (stream_enableB) begin
                for (i = 0; i < ROWS; i = i + 1) begin
                    output_dataB[i] <= bufferB[i][read_ptrB[i]];
                    if (read_ptrB[i] < COLS-1)
                        read_ptrB[i] <= read_ptrB[i] + 1;
                    else
                        read_ptrB[i] <= 0;
                end
            end

            if (load_enableC) begin
                for (i = 0; i < ROWS; i = i + 1) begin
                    bufferC[i][write_ptrC[i]] <= input_dataC[i];
                    if (write_ptrC[i] < COLS-1)
                        write_ptrC[i] <= write_ptrC[i] + 1;
                    else
                        write_ptrC[i] <= 0;
                end
            end else if (stream_enableC) begin
                for (i = 0; i < ROWS; i = i + 1) begin
                    output_dataC[i] <= bufferC[i][read_ptrC[i]];
                    if (read_ptrC[i] < COLS-1)
                        read_ptrC[i] <= read_ptrC[i] + 1;
                    else
                        read_ptrC[i] <= 0;
                end
            end
        end
    end

endmodule