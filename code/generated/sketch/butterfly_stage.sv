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