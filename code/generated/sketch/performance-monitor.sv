module PerformanceMonitor (
    input  logic clk,
    input  logic rst_n
);
    parameter COUNTER_WIDTH = 32;
    parameter WINDOW_SIZE   = 1024;

    typedef enum logic [2:0] {
        IDLE,
        MEASURE_UTIL,
        MEASURE_LAT,
        MEASURE_TPUT,
        UPDATE_STATS,
        DONE
    } state_t;

    state_t state, next_state;

    logic [COUNTER_WIDTH-1:0] cycle_count;
    logic [COUNTER_WIDTH-1:0] active_count;
    logic [COUNTER_WIDTH-1:0] latency_accum;
    logic [COUNTER_WIDTH-1:0] throughput_accum;
    logic [COUNTER_WIDTH-1:0] sample_count;

    logic [COUNTER_WIDTH-1:0] utilization;
    logic [COUNTER_WIDTH-1:0] avg_latency;
    logic [COUNTER_WIDTH-1:0] avg_throughput;

    logic measure_done;
    integer i, j;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            state <= IDLE;
        else
            state <= next_state;
    end

    always_comb begin
        next_state = state;
        measure_done = 1'b0;
        case (state)
            IDLE: begin
                next_state = MEASURE_UTIL;
            end
            MEASURE_UTIL: begin
                if (cycle_count >= WINDOW_SIZE)
                    next_state = MEASURE_LAT;
            end
            MEASURE_LAT: begin
                if (cycle_count >= WINDOW_SIZE*2)
                    next_state = MEASURE_TPUT;
            end
            MEASURE_TPUT: begin
                if (cycle_count >= WINDOW_SIZE*3)
                    next_state = UPDATE_STATS;
            end
            UPDATE_STATS: begin
                measure_done = 1'b1;
                next_state = DONE;
            end
            DONE: begin
                next_state = IDLE;
            end
        endcase
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cycle_count      <= '0;
            active_count     <= '0;
            latency_accum    <= '0;
            throughput_accum <= '0;
            sample_count     <= '0;
            utilization      <= '0;
            avg_latency      <= '0;
            avg_throughput   <= '0;
        end else begin
            cycle_count <= cycle_count + 1;
            case (state)
                MEASURE_UTIL: begin
                    active_count <= active_count + 1;
                end
                MEASURE_LAT: begin
                    latency_accum <= latency_accum + (cycle_count[7:0]);
                    sample_count  <= sample_count + 1;
                end
                MEASURE_TPUT: begin
                    throughput_accum <= throughput_accum + (cycle_count[7:0]);
                end
                UPDATE_STATS: begin
                    if (sample_count != 0) begin
                        utilization    <= (active_count * 100) / WINDOW_SIZE;
                        avg_latency    <= latency_accum / sample_count;
                        avg_throughput <= throughput_accum / sample_count;
                    end
                    for (i = 0; i < 1; i = i + 1) begin
                        for (j = 0; j < 1; j = j + 1) begin
                            cycle_count      <= '0;
                            active_count     <= '0;
                            latency_accum    <= '0;
                            throughput_accum <= '0;
                            sample_count     <= '0;
                        end
                    end
                end
                DONE: begin
                    if (measure_done) begin
                        for (i = 0; i < 1; i = i + 1) begin
                            for (j = 0; j < 1; j = j + 1) begin
                                utilization    <= utilization;
                                avg_latency    <= avg_latency;
                                avg_throughput <= avg_throughput;
                            end
                        end
                    end
                end
            endcase
        end
    end

endmodule