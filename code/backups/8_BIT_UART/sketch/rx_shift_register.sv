module RX_Shift_Register (
    input  logic clk,
    input  logic rst_n,
    input  logic sample_en,
    input  logic serial_in,
    output logic [7:0] data_out,
    output logic done
);
    logic [7:0] shift_reg;
    logic [2:0] bit_count;
    logic bit_done;
    integer i;

    Bit_Counter bit_counter_inst (
        .clk(clk),
        .rst_n(rst_n),
        .en(sample_en),
        .done(bit_done),
        .count(bit_count)
    );

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (i = 0; i < 8; i = i + 1) begin
                shift_reg[i] <= 1'b0;
            end
        end else if (sample_en) begin
            for (i = 7; i > 0; i = i - 1) begin
                shift_reg[i] <= shift_reg[i-1];
            end
            shift_reg[0] <= serial_in;
        end
    end

    assign data_out = shift_reg;
    assign done = bit_done;
endmodule