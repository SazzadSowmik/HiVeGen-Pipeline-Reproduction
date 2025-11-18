module FFT_Dataflow_Network (
    input  logic clk,
    input  logic rst_n
);
    typedef enum logic [1:0] {
        IDLE  = 2'b00,
        LOAD  = 2'b01,
        COMPUTE = 2'b10,
        STORE = 2'b11
    } fft_state_t;

    fft_state_t state, next_state;
    logic [3:0] stage_counter;
    logic load_done, compute_done, store_done;
    integer i;

    Butterfly_Stage stage0 (
        .clk(clk),
        .rst_n(rst_n)
    );

    Butterfly_Stage stage1 (
        .clk(clk),
        .rst_n(rst_n)
    );

    Butterfly_Stage stage2 (
        .clk(clk),
        .rst_n(rst_n)
    );

    Butterfly_Stage stage3 (
        .clk(clk),
        .rst_n(rst_n)
    );

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
            stage_counter <= 4'd0;
            load_done <= 1'b0;
            compute_done <= 1'b0;
            store_done <= 1'b0;
        end else begin
            state <= next_state;
            case (state)
                IDLE: begin
                    stage_counter <= 4'd0;
                    load_done <= 1'b0;
                    compute_done <= 1'b0;
                    store_done <= 1'b0;
                end
                LOAD: begin
                    if (stage_counter < 4'd3)
                        stage_counter <= stage_counter + 4'd1;
                    else
                        load_done <= 1'b1;
                end
                COMPUTE: begin
                    if (stage_counter < 4'd3)
                        stage_counter <= stage_counter + 4'd1;
                    else
                        compute_done <= 1'b1;
                end
                STORE: begin
                    if (stage_counter < 4'd3)
                        stage_counter <= stage_counter + 4'd1;
                    else
                        store_done <= 1'b1;
                end
                default: begin
                    load_done <= 1'b0;
                    compute_done <= 1'b0;
                    store_done <= 1'b0;
                end
            endcase
        end
    end

    always_comb begin
        next_state = state;
        case (state)
            IDLE: next_state = LOAD;
            LOAD: if (load_done) next_state = COMPUTE;
            COMPUTE: if (compute_done) next_state = STORE;
            STORE: if (store_done) next_state = IDLE;
            default: next_state = IDLE;
        endcase
    end
endmodule