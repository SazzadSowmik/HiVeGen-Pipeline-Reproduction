module TimingAndHandshakeUnit (
    input  logic clk,
    input  logic rst_n
);
    parameter NUM_PATHS = 8;
    parameter DATA_WIDTH = 16;

    logic [DATA_WIDTH-1:0] data_in [0:NUM_PATHS-1];
    logic [DATA_WIDTH-1:0] data_out [0:NUM_PATHS-1];
    logic valid_in [0:NUM_PATHS-1];
    logic ready_in [0:NUM_PATHS-1];
    logic valid_out [0:NUM_PATHS-1];
    logic ready_out [0:NUM_PATHS-1];
    logic handshake_done [0:NUM_PATHS-1];
    logic [DATA_WIDTH-1:0] buffer [0:NUM_PATHS-1];

    integer i;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (i = 0; i < NUM_PATHS; i = i + 1) begin
                data_in[i] <= '0;
                data_out[i] <= '0;
                valid_in[i] <= 1'b0;
                ready_in[i] <= 1'b0;
                valid_out[i] <= 1'b0;
                ready_out[i] <= 1'b0;
                handshake_done[i] <= 1'b0;
                buffer[i] <= '0;
            end
        end else begin
            for (i = 0; i < NUM_PATHS; i = i + 1) begin
                if (valid_in[i] && ready_in[i]) begin
                    buffer[i] <= data_in[i];
                    handshake_done[i] <= 1'b1;
                    valid_out[i] <= 1'b1;
                end else if (valid_out[i] && ready_out[i]) begin
                    data_out[i] <= buffer[i];
                    handshake_done[i] <= 1'b0;
                    valid_out[i] <= 1'b0;
                end
            end
        end
    end

    always_comb begin
        for (i = 0; i < NUM_PATHS; i = i + 1) begin
            ready_in[i] = ~handshake_done[i];
            ready_out[i] = handshake_done[i];
        end
    end

endmodule