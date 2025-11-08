module Parity_Generator_Checker (
    input  logic [7:0] data,
    input  logic parity_mode, 
    input  logic check_en,
    output logic parity_bit,
    output logic parity_error
);
    integer i;
    logic parity_calc;
    logic parity_expected;

    always_comb begin
        parity_calc = 1'b0;
        for (i = 0; i < 8; i = i + 1) begin
            parity_calc = parity_calc ^ data[i];
        end
        if (parity_mode == 1'b0) begin
            parity_bit = parity_calc;
        end else begin
            parity_bit = ~parity_calc;
        end
    end

    always_comb begin
        parity_error = 1'b0;
        if (check_en) begin
            parity_expected = 1'b0;
            for (i = 0; i < 8; i = i + 1) begin
                parity_expected = parity_expected ^ data[i];
            end
            if (parity_mode == 1'b1) begin
                parity_expected = ~parity_expected;
            end
            if (parity_expected != parity_bit) begin
                parity_error = 1'b1;
            end
        end
    end
endmodule