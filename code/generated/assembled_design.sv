
// ---- GPE ----
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

// ---- GIB ----
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

// ---- CGRA_Array ----
module CGRA_Array (
    input  logic clk,
    input  logic rst_n
);
    GPE gpe_inst[0:1][0:3];
    GIB gib_inst[0:1][0:3];
    integer i, j;

    generate
        for (i = 0; i < 2; i = i + 1) begin : gen_row
            for (j = 0; j < 4; j = j + 1) begin : gen_col
                GPE u_gpe (
                    .clk(clk),
                    .rst_n(rst_n)
                );
                GIB u_gib (
                    .clk(clk),
                    .rst_n(rst_n)
                );
            end
        end
    endgenerate
endmodule

// ---- Scratchpad_Bank ----
module Scratchpad_Bank (
    input  logic clk,
    input  logic rst_n
);
    logic [31:0] mem [0:2047];
    logic [31:0] rdata;
    logic [31:0] wdata;
    logic [10:0] addr;
    logic        we;

    integer i;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (i = 0; i < 2048; i = i + 1) begin
                mem[i] <= 32'd0;
            end
        end else begin
            if (we) begin
                mem[addr] <= wdata;
            end
        end
    end

    always_ff @(posedge clk) begin
        rdata <= mem[addr];
    end
endmodule

// ---- Scratchpad_Memory_System ----
module Scratchpad_Memory_System (
    input  logic clk,
    input  logic rst_n
);
    genvar i;
    generate
        for (i = 0; i < 8; i = i + 1) begin : BANKS
            Scratchpad_Bank bank_inst (
                .clk   (clk),
                .rst_n (rst_n)
            );
        end
    endgenerate
endmodule

// ---- DMA_Controller ----
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

// ---- Configuration_Controller ----
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

// ---- Butterfly_Stage ----
module Butterfly_Stage (
    input  logic clk,
    input  logic rst_n
);
    typedef struct packed {
        logic signed [15:0] re;
        logic signed [15:0] im;
    } complex_t;

    complex_t a_in [0:3];
    complex_t b_in [0:3];
    complex_t twiddle [0:3];
    complex_t a_out [0:3];
    complex_t b_out [0:3];

    integer i;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (i = 0; i < 4; i = i + 1) begin
                a_in[i].re <= 16'sd0;
                a_in[i].im <= 16'sd0;
                b_in[i].re <= 16'sd0;
                b_in[i].im <= 16'sd0;
                twiddle[i].re <= 16'sd0;
                twiddle[i].im <= 16'sd0;
                a_out[i].re <= 16'sd0;
                a_out[i].im <= 16'sd0;
                b_out[i].re <= 16'sd0;
                b_out[i].im <= 16'sd0;
            end
        end else begin
            for (i = 0; i < 4; i = i + 1) begin
                logic signed [31:0] mult_re;
                logic signed [31:0] mult_im;
                mult_re = (b_in[i].re * twiddle[i].re) - (b_in[i].im * twiddle[i].im);
                mult_im = (b_in[i].re * twiddle[i].im) + (b_in[i].im * twiddle[i].re);
                a_out[i].re <= a_in[i].re + mult_re[30:15];
                a_out[i].im <= a_in[i].im + mult_im[30:15];
                b_out[i].re <= a_in[i].re - mult_re[30:15];
                b_out[i].im <= a_in[i].im - mult_im[30:15];
            end
        end
    end
endmodule

// ---- FFT_Dataflow_Network ----
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

// ---- System_Bus_Interface ----
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

// ---- CGRA_FFT_Accelerator ----
module CGRA_FFT_Accelerator (
    input  logic clk,
    input  logic rst_n
);
    CGRA_Array u_cgra_array (
        .clk(clk),
        .rst_n(rst_n)
    );

    Scratchpad_Memory_System u_scratchpad (
        .clk(clk),
        .rst_n(rst_n)
    );

    DMA_Controller u_dma (
        .clk(clk),
        .rst_n(rst_n)
    );

    Configuration_Controller u_config (
        .clk(clk),
        .rst_n(rst_n)
    );

    FFT_Dataflow_Network u_fft_network (
        .clk(clk),
        .rst_n(rst_n)
    );

    System_Bus_Interface u_sysbus (
        .clk(clk),
        .rst_n(rst_n)
    );
endmodule
