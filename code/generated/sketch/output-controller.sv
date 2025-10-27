module OutputController (
    input  logic clk,
    input  logic rst_n
);
    parameter TILE_ROWS = 4;
    parameter TILE_COLS = 64;
    parameter DATA_WIDTH = 16;
    parameter MEM_BW = 8;

    logic [DATA_WIDTH-1:0] c_tile [0:TILE_ROWS-1][0:TILE_COLS-1];
    logic [DATA_WIDTH-1:0] mem_write_data [0:MEM_BW-1];
    logic [15:0] mem_addr;
    logic mem_write_en;
    logic [5:0] row_ptr;
    logic [5:0] col_ptr;
    logic [3:0] bw_ptr;

    typedef enum logic [1:0] {
        IDLE,
        PREPARE,
        WRITE,
        DONE
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
        mem_write_en = 1'b0;
        case (state)
            IDLE: begin
                next_state = PREPARE;
            end
            PREPARE: begin
                next_state = WRITE;
            end
            WRITE: begin
                mem_write_en = 1'b1;
                if ((row_ptr == TILE_ROWS-1) && (col_ptr >= TILE_COLS))
                    next_state = DONE;
            end
            DONE: begin
                next_state = IDLE;
            end
        endcase
    end

    integer i, j, k;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            row_ptr <= 0;
            col_ptr <= 0;
            bw_ptr <= 0;
            mem_addr <= 0;
            for (i = 0; i < TILE_ROWS; i = i + 1) begin
                for (j = 0; j < TILE_COLS; j = j + 1) begin
                    c_tile[i][j] <= '0;
                end
            end
            for (k = 0; k < MEM_BW; k = k + 1) begin
                mem_write_data[k] <= '0;
            end
        end else begin
            case (state)
                PREPARE: begin
                    row_ptr <= 0;
                    col_ptr <= 0;
                    bw_ptr <= 0;
                    mem_addr <= 0;
                end
                WRITE: begin
                    if (mem_write_en) begin
                        for (k = 0; k < MEM_BW; k = k + 1) begin
                            if ((col_ptr + k) < TILE_COLS)
                                mem_write_data[k] <= c_tile[row_ptr][col_ptr + k];
                            else
                                mem_write_data[k] <= '0;
                        end
                        mem_addr <= mem_addr + MEM_BW;
                        col_ptr <= col_ptr + MEM_BW;
                        if (col_ptr + MEM_BW >= TILE_COLS) begin
                            col_ptr <= 0;
                            if (row_ptr < TILE_ROWS-1)
                                row_ptr <= row_ptr + 1;
                            else
                                row_ptr <= TILE_ROWS-1;
                        end
                    end
                end
                DONE: begin
                    row_ptr <= 0;
                    col_ptr <= 0;
                    bw_ptr <= 0;
                end
                default: begin
                    row_ptr <= row_ptr;
                    col_ptr <= col_ptr;
                end
            endcase
        end
    end

endmodule