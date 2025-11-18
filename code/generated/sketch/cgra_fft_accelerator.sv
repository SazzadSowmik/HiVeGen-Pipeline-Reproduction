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