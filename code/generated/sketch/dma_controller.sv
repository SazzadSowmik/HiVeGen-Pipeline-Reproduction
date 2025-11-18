module DMA_Controller (
    input  logic clk,
    input  logic rst_n
);
    typedef enum logic [2:0] {
        IDLE        = 3'b000,
        READ_REQ    = 3'b001,
        READ_BURST  = 3'b010,
        WRITE_REQ   = 3'b011,
        WRITE_BURST = 3'b100,
        COMPLETE    = 3'b101
    } dma_state_t;

    dma_state_t state, next_state;
    logic [4:0] burst_count;
    logic [4:0] beat_counter;
    logic [31:0] mem_buffer [0:31];
    logic [31:0] next_mem_buffer [0:31];
    logic transfer_done;
    integer i;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
            burst_count <= 5'd0;
            beat_counter <= 5'd0;
            transfer_done <= 1'b0;
            for (i = 0; i < 32; i = i + 1) begin
                mem_buffer[i] <= 32'd0;
                next_mem_buffer[i] <= 32'd0;
            end
        end else begin
            state <= next_state;
            case (state)
                IDLE: begin
                    burst_count <= 5'd0;
                    beat_counter <= 5'd0;
                    transfer_done <= 1'b0;
                end
                READ_REQ: begin
                    burst_count <= 5'd16;
                    transfer_done <= 1'b0;
                end
                READ_BURST: begin
                    if (beat_counter < burst_count) begin
                        beat_counter <= beat_counter + 5'd1;
                        for (i = 0; i < 32; i = i + 1) begin
                            mem_buffer[i] <= next_mem_buffer[i];
                        end
                    end else begin
                        transfer_done <= 1'b1;
                    end
                end
                WRITE_REQ: begin
                    transfer_done <= 1'b0;
                    beat_counter <= 5'd0;
                end
                WRITE_BURST: begin
                    if (beat_counter < burst_count) begin
                        beat_counter <= beat_counter + 5'd1;
                    end else begin
                        transfer_done <= 1'b1;
                    end
                end
                COMPLETE: begin
                    transfer_done <= 1'b0;
                end
                default: begin
                    transfer_done <= 1'b0;
                end
            endcase
        end
    end

    always_comb begin
        next_state = state;
        case (state)
            IDLE: begin
                next_state = READ_REQ;
            end
            READ_REQ: begin
                next_state = READ_BURST;
            end
            READ_BURST: begin
                if (transfer_done)
                    next_state = WRITE_REQ;
            end
            WRITE_REQ: begin
                next_state = WRITE_BURST;
            end
            WRITE_BURST: begin
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