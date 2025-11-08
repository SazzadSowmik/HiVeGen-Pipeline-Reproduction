module TX_Shift_Register (
    input  logic        clk,
    input  logic        rst_n,
    input  logic        load,
    input  logic        shift_en,
    input  logic [7:0]  data_in,
    output logic        serial_out,
    output logic        done
);
    logic [7:0] shift_reg;
    logic [2:0] bit_count;
    logic       bit_done;
    integer i;

    Bit_Counter u_bit_counter (
        .clk   (clk),
        .rst_n (rst_n),
        .en    (shift_en),
        .done  (bit_done),
        .count (bit_count)
    );

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (i = 0; i < 8; i = i + 1) begin
                shift_reg[i] <= 1'b0;
            end
        end else if (load) begin
            for (i = 0; i < 8; i = i + 1) begin
                shift_reg[i] <= data_in[i];
            end
        end else if (shift_en) begin
            for (i = 0; i < 7; i = i + 1) begin
                shift_reg[i] <= shift_reg[i+1];
            end
            shift_reg[7] <= 1'b0;
        end
    end

    assign serial_out = shift_reg[0];
    assign done = bit_done;
endmodule