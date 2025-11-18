module Configuration_Controller (
    input  logic clk,
    input  logic rst_n
);
    typedef enum logic [1:0] {
        IDLE   = 2'b00,
        LOAD   = 2'b01,
        APPLY  = 2'b10
    } cfg_state_t;

    cfg_state_t state, next_state;
    logic [31:0] config_data [0:255];
    logic [31:0] next_config_data [0:255];
    logic [7:0]  addr_counter;
    logic load_done;
    integer i;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
            addr_counter <= 8'd0;
            load_done <= 1'b0;
            for (i = 0; i < 256; i = i + 1) begin
                config_data[i] <= 32'd0;
                next_config_data[i] <= 32'd0;
            end
        end else begin
            state <= next_state;
            case (state)
                IDLE: begin
                    addr_counter <= 8'd0;
                    load_done <= 1'b0;
                end
                LOAD: begin
                    if (addr_counter < 8'd255) begin
                        addr_counter <= addr_counter + 8'd1;
                        next_config_data[addr_counter] <= addr_counter;
                    end else begin
                        load_done <= 1'b1;
                    end
                end
                APPLY: begin
                    for (i = 0; i < 256; i = i + 1) begin
                        config_data[i] <= next_config_data[i];
                    end
                    load_done <= 1'b0;
                end
                default: begin
                    load_done <= 1'b0;
                end
            endcase
        end
    end

    always_comb begin
        next_state = state;
        case (state)
            IDLE: next_state = LOAD;
            LOAD: if (load_done) next_state = APPLY;
            APPLY: next_state = IDLE;
            default: next_state = IDLE;
        endcase
    end
endmodule