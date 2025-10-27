// ===================================================================
// Wrapper Module with Input/Output Ports
// ===================================================================
module SystolicArray_GEMM_4x4_Wrapper (
    input  logic clk,
    input  logic rst_n,
    input  logic signed [15:0] a_in_0, a_in_1, a_in_2, a_in_3,
    input  logic signed [15:0] b_in_0, b_in_1, b_in_2, b_in_3,
    output logic signed [31:0] c_out_0_0, c_out_0_1, c_out_0_2, c_out_0_3,
    output logic signed [31:0] c_out_1_0, c_out_1_1, c_out_1_2, c_out_1_3,
    output logic signed [31:0] c_out_2_0, c_out_2_1, c_out_2_2, c_out_2_3,
    output logic signed [31:0] c_out_3_0, c_out_3_1, c_out_3_2, c_out_3_3
);
    localparam int N = 4;
    typedef logic signed [15:0] data_t;
    typedef logic signed [31:0] acc_t;

    data_t a_pipe [0:N-1][0:N-1];
    data_t b_pipe [0:N-1][0:N-1];
    acc_t  c_acc  [0:N-1][0:N-1];

    integer i, j;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (i = 0; i < N; i = i + 1) begin
                for (j = 0; j < N; j = j + 1) begin
                    a_pipe[i][j] <= '0;
                    b_pipe[i][j] <= '0;
                    c_acc[i][j]  <= '0;
                end
            end
        end else begin
            // Inject inputs at the top and left edges
            a_pipe[0][0] <= a_in_0;
            a_pipe[0][1] <= a_in_1;
            a_pipe[0][2] <= a_in_2;
            a_pipe[0][3] <= a_in_3;
            
            b_pipe[0][0] <= b_in_0;
            b_pipe[1][0] <= b_in_1;
            b_pipe[2][0] <= b_in_2;
            b_pipe[3][0] <= b_in_3;
            
            // Systolic array logic
            for (i = 0; i < N; i = i + 1) begin
                for (j = 0; j < N; j = j + 1) begin
                    // Flow A downward (skip row 0 as it gets inputs)
                    if (i > 0)
                        a_pipe[i][j] <= a_pipe[i-1][j];
                    
                    // Flow B rightward (skip column 0 as it gets inputs)
                    if (j > 0)
                        b_pipe[i][j] <= b_pipe[i][j-1];
                    
                    // MAC operation
                    c_acc[i][j] <= c_acc[i][j] + a_pipe[i][j] * b_pipe[i][j];
                end
            end
        end
    end
    
    // Output assignments
    assign c_out_0_0 = c_acc[0][0];
    assign c_out_0_1 = c_acc[0][1];
    assign c_out_0_2 = c_acc[0][2];
    assign c_out_0_3 = c_acc[0][3];
    assign c_out_1_0 = c_acc[1][0];
    assign c_out_1_1 = c_acc[1][1];
    assign c_out_1_2 = c_acc[1][2];
    assign c_out_1_3 = c_acc[1][3];
    assign c_out_2_0 = c_acc[2][0];
    assign c_out_2_1 = c_acc[2][1];
    assign c_out_2_2 = c_acc[2][2];
    assign c_out_2_3 = c_acc[2][3];
    assign c_out_3_0 = c_acc[3][0];
    assign c_out_3_1 = c_acc[3][1];
    assign c_out_3_2 = c_acc[3][2];
    assign c_out_3_3 = c_acc[3][3];

endmodule

// ===================================================================
// Testbench for SystolicArray_GEMM_4x4
// ===================================================================
module tb_SystolicArray_GEMM_4x4;

    // Testbench signals
    logic clk;
    logic rst_n;
    
    // Input signals
    logic signed [15:0] a_in_0, a_in_1, a_in_2, a_in_3;
    logic signed [15:0] b_in_0, b_in_1, b_in_2, b_in_3;
    
    // Output signals
    logic signed [31:0] c_out_0_0, c_out_0_1, c_out_0_2, c_out_0_3;
    logic signed [31:0] c_out_1_0, c_out_1_1, c_out_1_2, c_out_1_3;
    logic signed [31:0] c_out_2_0, c_out_2_1, c_out_2_2, c_out_2_3;
    logic signed [31:0] c_out_3_0, c_out_3_1, c_out_3_2, c_out_3_3;

    // Instantiate DUT
    SystolicArray_GEMM_4x4_Wrapper dut (
        .clk(clk),
        .rst_n(rst_n),
        .a_in_0(a_in_0), .a_in_1(a_in_1), .a_in_2(a_in_2), .a_in_3(a_in_3),
        .b_in_0(b_in_0), .b_in_1(b_in_1), .b_in_2(b_in_2), .b_in_3(b_in_3),
        .c_out_0_0(c_out_0_0), .c_out_0_1(c_out_0_1), .c_out_0_2(c_out_0_2), .c_out_0_3(c_out_0_3),
        .c_out_1_0(c_out_1_0), .c_out_1_1(c_out_1_1), .c_out_1_2(c_out_1_2), .c_out_1_3(c_out_1_3),
        .c_out_2_0(c_out_2_0), .c_out_2_1(c_out_2_1), .c_out_2_2(c_out_2_2), .c_out_2_3(c_out_2_3),
        .c_out_3_0(c_out_3_0), .c_out_3_1(c_out_3_1), .c_out_3_2(c_out_3_2), .c_out_3_3(c_out_3_3)
    );

    // Clock generation: 10ns period (100MHz)
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    // Test matrices
    logic signed [15:0] test_a [0:3][0:3];
    logic signed [15:0] test_b [0:3][0:3];

    // Task to initialize test matrices
    task initialize_matrices();
        // Matrix A: Simple incremental pattern
        test_a[0][0] = 1;  test_a[0][1] = 2;  test_a[0][2] = 3;  test_a[0][3] = 4;
        test_a[1][0] = 5;  test_a[1][1] = 6;  test_a[1][2] = 7;  test_a[1][3] = 8;
        test_a[2][0] = 9;  test_a[2][1] = 10; test_a[2][2] = 11; test_a[2][3] = 12;
        test_a[3][0] = 13; test_a[3][1] = 14; test_a[3][2] = 15; test_a[3][3] = 16;

        // Matrix B: Identity matrix
        test_b[0][0] = 1; test_b[0][1] = 0; test_b[0][2] = 0; test_b[0][3] = 0;
        test_b[1][0] = 0; test_b[1][1] = 1; test_b[1][2] = 0; test_b[1][3] = 0;
        test_b[2][0] = 0; test_b[2][1] = 0; test_b[2][2] = 1; test_b[2][3] = 0;
        test_b[3][0] = 0; test_b[3][1] = 0; test_b[3][2] = 0; test_b[3][3] = 1;
    endtask

    // Task to feed data in systolic pattern
    task feed_systolic_data();
        int cycle;
        
        $display("\nFeeding data in systolic pattern...");
        
        // Initialize inputs to zero
        a_in_0 = 0; a_in_1 = 0; a_in_2 = 0; a_in_3 = 0;
        b_in_0 = 0; b_in_1 = 0; b_in_2 = 0; b_in_3 = 0;
        
        // Cycle 0: First elements
        @(posedge clk);
        a_in_0 = test_a[0][0];
        b_in_0 = test_b[0][0];
        
        // Cycle 1: Stagger inputs
        @(posedge clk);
        a_in_0 = test_a[0][1];
        a_in_1 = test_a[1][0];
        b_in_0 = test_b[0][1];
        b_in_1 = test_b[1][0];
        
        // Cycle 2
        @(posedge clk);
        a_in_0 = test_a[0][2];
        a_in_1 = test_a[1][1];
        a_in_2 = test_a[2][0];
        b_in_0 = test_b[0][2];
        b_in_1 = test_b[1][1];
        b_in_2 = test_b[2][0];
        
        // Cycle 3
        @(posedge clk);
        a_in_0 = test_a[0][3];
        a_in_1 = test_a[1][2];
        a_in_2 = test_a[2][1];
        a_in_3 = test_a[3][0];
        b_in_0 = test_b[0][3];
        b_in_1 = test_b[1][2];
        b_in_2 = test_b[2][1];
        b_in_3 = test_b[3][0];
        
        // Cycle 4
        @(posedge clk);
        a_in_0 = 0;
        a_in_1 = test_a[1][3];
        a_in_2 = test_a[2][2];
        a_in_3 = test_a[3][1];
        b_in_0 = 0;
        b_in_1 = test_b[1][3];
        b_in_2 = test_b[2][2];
        b_in_3 = test_b[3][1];
        
        // Cycle 5
        @(posedge clk);
        a_in_0 = 0;
        a_in_1 = 0;
        a_in_2 = test_a[2][3];
        a_in_3 = test_a[3][2];
        b_in_0 = 0;
        b_in_1 = 0;
        b_in_2 = test_b[2][3];
        b_in_3 = test_b[3][2];
        
        // Cycle 6
        @(posedge clk);
        a_in_0 = 0;
        a_in_1 = 0;
        a_in_2 = 0;
        a_in_3 = test_a[3][3];
        b_in_0 = 0;
        b_in_1 = 0;
        b_in_2 = 0;
        b_in_3 = test_b[3][3];
        
        // Flush with zeros
        @(posedge clk);
        a_in_0 = 0; a_in_1 = 0; a_in_2 = 0; a_in_3 = 0;
        b_in_0 = 0; b_in_1 = 0; b_in_2 = 0; b_in_3 = 0;
    endtask

    // Task to display results
    task display_results();
        $display("\n=== Final Results ===");
        $display("C Accumulator Matrix:");
        $display("  [%6d %6d %6d %6d]", c_out_0_0, c_out_0_1, c_out_0_2, c_out_0_3);
        $display("  [%6d %6d %6d %6d]", c_out_1_0, c_out_1_1, c_out_1_2, c_out_1_3);
        $display("  [%6d %6d %6d %6d]", c_out_2_0, c_out_2_1, c_out_2_2, c_out_2_3);
        $display("  [%6d %6d %6d %6d]", c_out_3_0, c_out_3_1, c_out_3_2, c_out_3_3);
        
        $display("\nExpected (A * Identity = A):");
        $display("  [%6d %6d %6d %6d]", test_a[0][0], test_a[0][1], test_a[0][2], test_a[0][3]);
        $display("  [%6d %6d %6d %6d]", test_a[1][0], test_a[1][1], test_a[1][2], test_a[1][3]);
        $display("  [%6d %6d %6d %6d]", test_a[2][0], test_a[2][1], test_a[2][2], test_a[2][3]);
        $display("  [%6d %6d %6d %6d]", test_a[3][0], test_a[3][1], test_a[3][2], test_a[3][3]);
        $display("=====================\n");
    endtask

    // Main test sequence
    initial begin
        // Setup waveform dumping
        $dumpfile("systolic_array.vcd");
        $dumpvars(0, tb_SystolicArray_GEMM_4x4);

        // Initialize
        initialize_matrices();
        
        a_in_0 = 0; a_in_1 = 0; a_in_2 = 0; a_in_3 = 0;
        b_in_0 = 0; b_in_1 = 0; b_in_2 = 0; b_in_3 = 0;

        $display("\n========================================");
        $display("  Systolic Array 4x4 GEMM Testbench");
        $display("========================================");

        $display("\nTest Matrix A:");
        $display("  [%4d %4d %4d %4d]", test_a[0][0], test_a[0][1], test_a[0][2], test_a[0][3]);
        $display("  [%4d %4d %4d %4d]", test_a[1][0], test_a[1][1], test_a[1][2], test_a[1][3]);
        $display("  [%4d %4d %4d %4d]", test_a[2][0], test_a[2][1], test_a[2][2], test_a[2][3]);
        $display("  [%4d %4d %4d %4d]", test_a[3][0], test_a[3][1], test_a[3][2], test_a[3][3]);
        
        $display("\nTest Matrix B (Identity):");
        $display("  [%4d %4d %4d %4d]", test_b[0][0], test_b[0][1], test_b[0][2], test_b[0][3]);
        $display("  [%4d %4d %4d %4d]", test_b[1][0], test_b[1][1], test_b[1][2], test_b[1][3]);
        $display("  [%4d %4d %4d %4d]", test_b[2][0], test_b[2][1], test_b[2][2], test_b[2][3]);
        $display("  [%4d %4d %4d %4d]", test_b[3][0], test_b[3][1], test_b[3][2], test_b[3][3]);

        // Apply reset
        $display("\nApplying reset...");
        rst_n = 0;
        repeat(3) @(posedge clk);
        rst_n = 1;
        @(posedge clk);

        // Feed data
        feed_systolic_data();
        
        // Wait for computation
        $display("Waiting for computation to complete...");
        repeat(15) @(posedge clk);
        
        // Display results
        display_results();

        $display("Simulation completed at time %0t ns\n", $time);
        $finish;
    end

    // Timeout watchdog
    initial begin
        #5000;
        $display("\n*** ERROR: Simulation timeout! ***\n");
        $finish;
    end

endmodule