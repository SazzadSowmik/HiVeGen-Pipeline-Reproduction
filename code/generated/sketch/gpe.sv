module GPE (
    input  logic clk,
    input  logic rst_n
);
    typedef enum logic [1:0] {
        IDLE  = 2'b00,
        EXEC  = 2'b01,
        DELAY = 2'b10
    } gpe_state_t;

    gpe_state_t state, next_state;
    logic [15:0] reg_file [0:3];
    logic [15:0] next_reg_file [0:3];
    logic [15:0] alu_a, alu_b, alu_result;
    logic [1:0]  alu_op;
    logic [3:0]  delay_counter;
    integer i;

    always_comb begin
        case (alu_op)
            2'b00: alu_result = alu_a + alu_b;
            2'b01: alu_result = alu_a - alu_b;
            2'b10: alu_result = alu_a * alu_b;
            default: alu_result = 16'd0;
        endcase
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
            delay_counter <= 4'd0;
            alu_op <= 2'b00;
            alu_a <= 16'd0;
            alu_b <= 16'd0;
            for (i = 0; i < 4; i = i + 1) begin
                reg_file[i] <= 16'd0;
                next_reg_file[i] <= 16'd0;
            end
        end else begin
            state <= next_state;
            case (state)
                IDLE: begin
                    alu_op <= 2'b00;
                    alu_a <= reg_file[0];
                    alu_b <= reg_file[1];
                    delay_counter <= 4'd0;
                end
                EXEC: begin
                    next_reg_file[0] <= alu_result;
                    for (i = 1; i < 4; i = i + 1) begin
                        next_reg_file[i] <= reg_file[i];
                    end
                    for (i = 0; i < 4; i = i + 1) begin
                        reg_file[i] <= next_reg_file[i];
                    end
                    delay_counter <= delay_counter + 4'd1;
                end
                DELAY: begin
                    if (delay_counter < 4'd8)
                        delay_counter <= delay_counter + 4'd1;
                    else
                        delay_counter <= 4'd0;
                end
                default: begin
                    delay_counter <= 4'd0;
                end
            endcase
        end
    end

    always_comb begin
        next_state = state;
        case (state)
            IDLE: next_state = EXEC;
            EXEC: next_state = DELAY;
            DELAY: if (delay_counter == 4'd0) next_state = IDLE;
            default: next_state = IDLE;
        endcase
    end
endmodule