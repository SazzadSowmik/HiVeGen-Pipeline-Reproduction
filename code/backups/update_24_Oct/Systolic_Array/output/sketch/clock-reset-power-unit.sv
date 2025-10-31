module ClockResetPowerUnit (
    input  logic clk,
    input  logic rst_n
);
    parameter integer SYNC_STAGES = 2;
    parameter integer NUM_GATES   = 4;

    logic [SYNC_STAGES-1:0] rst_sync;
    logic rst_int_n;
    logic [NUM_GATES-1:0] clk_en;
    logic [NUM_GATES-1:0] gated_clk;
    logic [NUM_GATES-1:0] power_state;
    integer i, j;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (i = 0; i < SYNC_STAGES; i = i + 1) begin
                rst_sync[i] <= 1'b0;
            end
        end else begin
            rst_sync[0] <= 1'b1;
            for (i = 1; i < SYNC_STAGES; i = i + 1) begin
                rst_sync[i] <= rst_sync[i-1];
            end
        end
    end

    assign rst_int_n = rst_sync[SYNC_STAGES-1];

    always_ff @(posedge clk or negedge rst_int_n) begin
        if (!rst_int_n) begin
            for (i = 0; i < NUM_GATES; i = i + 1) begin
                clk_en[i] <= 1'b0;
                power_state[i] <= 1'b0;
            end
        end else begin
            for (i = 0; i < NUM_GATES; i = i + 1) begin
                clk_en[i] <= ~clk_en[i];
                power_state[i] <= clk_en[i];
            end
        end
    end

    always_comb begin
        for (i = 0; i < NUM_GATES; i = i + 1) begin
            gated_clk[i] = clk & clk_en[i];
        end
    end

endmodule