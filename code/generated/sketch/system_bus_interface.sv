module System_Bus_Interface (
    input  logic clk,
    input  logic rst_n
);
    typedef enum logic [1:0] {
        IDLE    = 2'b00,
        CONFIG  = 2'b01,
        TRANSFER= 2'b10,
        COMPLETE= 2'b11
    } bus_state_t;

    bus_state_t state, next_state;
    logic [63:0] config_reg [0:3];
    logic [63:0] data_buffer [0:7];
    logic [3:0]  config_index;
    logic [3:0]  data_index;
    logic        config_done;
    logic        transfer_done;
    integer i;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
            config_index <= 4'd0;
            data_index <= 4'd0;
            config_done <= 1'b0;
            transfer_done <= 1'b0;
            for (i = 0; i < 4; i = i + 1) begin
                config_reg[i] <= 64'd0;
            end
            for (i = 0; i < 8; i = i + 1) begin
                data_buffer[i] <= 64'd0;
            end
        end else begin
            state <= next_state;
            case (state)
                IDLE: begin
                    config_index <= 4'd0;
                    data_index <= 4'd0;
                    config_done <= 1'b0;
                    transfer_done <= 1'b0;
                end
                CONFIG: begin
                    if (config_index < 4'd4) begin
                        config_reg[config_index] <= config_reg[config_index] + 64'd1;
                        config_index <= config_index + 4'd1;
                    end else begin
                        config_done <= 1'b1;
                    end
                end
                TRANSFER: begin
                    if (data_index < 4'd8) begin
                        data_buffer[data_index] <= data_buffer[data_index] + 64'd2;
                        data_index <= data_index + 4'd1;
                    end else begin
                        transfer_done <= 1'b1;
                    end
                end
                COMPLETE: begin
                    for (i = 0; i < 8; i = i + 1) begin
                        data_buffer[i] <= 64'd0;
                    end
                    config_done <= 1'b0;
                    transfer_done <= 1'b0;
                end
                default: begin
                    config_done <= 1'b0;
                    transfer_done <= 1'b0;
                end
            endcase
        end
    end

    always_comb begin
        next_state = state;
        case (state)
            IDLE: begin
                next_state = CONFIG;
            end
            CONFIG: begin
                if (config_done)
                    next_state = TRANSFER;
            end
            TRANSFER: begin
                if (transfer_done)
                    next_state = COMPLETE;
            end
            COMPLETE: begin
                next_state = IDLE;
            end
            default: next_state = IDLE;
        endcase
    end
endmodule