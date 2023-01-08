`include "defs.svh"
`include "alu_op.svh"

module alu(
    input logic [7:0] a_i,
    input logic [7:0] b_i,
    input alu_op_e op_i,
    input logic carry_i,
    output logic [7:0] res_o,
    output logic overflow_o,
    output logic carry_o
);

logic [8:0] tmp_adc, tmp_sbc;
logic [7:0] tmp_b;

always_comb begin
    overflow_o = '0;
    carry_o = '0;

    tmp_adc = a_i + b_i + {8'b0, carry_i};
    tmp_sbc = a_i - b_i - {8'b0, !carry_i};
    tmp_b = 8'hFF - b_i;

    case (op_i)
        AluOpAdc: begin
            res_o = tmp_adc[7:0];
            overflow_o = (a_i[7] ^ res_o[7]) & (b_i[7] ^ res_o[7]);
            carry_o = tmp_adc[8];
        end
        AluOpSbc: begin
            res_o = tmp_sbc[7:0];
            overflow_o = (a_i[7] ^ res_o[7]) & (tmp_b[7] ^ res_o[7]);
            carry_o = !tmp_sbc[8];
        end
        AluOpAnd: res_o = a_i & b_i;
        AluOpXor: res_o = a_i ^ b_i;
        AluOpOr:  res_o = a_i | b_i;
        AluOpShiftL: begin
            res_o = {a_i[6:0], carry_i};
            carry_o = a_i[7];
        end
        AluOpShiftR: begin
            res_o = {carry_i, a_i[7:1]};
            carry_o = a_i[0];
        end
        default: begin
            res_o = '0;
        end
    endcase
end

endmodule
