module GIB (
    input  logic clk,
    input  logic rst_n
);
    typedef enum logic [1:0] {
        IDLE   = 2'b00,
        ROUTE  = 2'b01,
        UPDATE = 2'b10
    } gib_state_t;

    gib_state_t state, next_state;
    logic [3:0] route_table [0:3][0:3];
    logic [3:0] next_route_table [0:3][0:3];
    logic [3:0] config_counter;
    logic update_done;
    integer i, j;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
            config_counter <= 4'd0;
            update_done <= 1'b0;
            for (i = 0; i < 4; i = i + 1) begin
                for (j = 0; j < 4; j = j + 1) begin
                    route_table[i][j] <= 4'd0;
                    next_route_table[i][j] <= 4'd0;
                end
            end
        end else begin
            state <= next_state;
            case (state)
                IDLE: begin
                    config_counter <= 4'd0;
                    update_done <= 1'b0;
                end
                ROUTE: begin
                    if (config_counter < 4'd8)
                        config_counter <= config_counter + 4'd1;
                    else
                        update_done <= 1'b1;
                end
                UPDATE: begin
                    for (i = 0; i < 4; i = i + 1) begin
                        for (j = 0; j < 4; j = j + 1) begin
                            route_table[i][j] <= next_route_table[i][j];
                        end
                    end
                    update_done <= 1'b0;
                end
                default: begin
                    update_done <= 1'b0;
                end
            endcase
        end
    end

    always_comb begin
        next_state = state;
        case (state)
            IDLE: next_state = ROUTE;
            ROUTE: if (update_done) next_state = UPDATE;
            UPDATE: next_state = IDLE;
            default: next_state = IDLE;
        endcase
    end
endmodule