`timescale 1ns / 1ps

module testbench;

// Testbench signals
reg [5:0] sel;
reg [63:0] in;
wire out;
integer i;  // declare at the start of the block

// Instantiate the mux64_1 module
mux64to1_pipelined uut (
    .sel(sel),
    .in(in),
    .out(out)
);

// Test procedure
initial begin
    // Initialize inputs
    sel = 0;
    in = 64'hA5A5_A5A5_F0F0_0F0F; // Example input pattern, hexadecimal for clarity

    // Initialize the test loop
    for (i = 0; i < 64; i = i + 1) begin
        #10 sel = i;  // Set selection to current index
        // Use a temporary variable for clarity and to ensure the compiler
        // treats it as a single bit select in a simulation context
        #10 begin
            reg expected_out;
            expected_out = in[i]; // Use the loop counter directly for bit select
            if (out == expected_out)
                $display("Test %d passed! Output: %b, Expected: %b", i, out, expected_out);
            else
                $display("Test %d failed! Output: %b, Expected: %b", i, out, expected_out);
        end
    end

    // End of tests
    #10 $finish;
end

endmodule
