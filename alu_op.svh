`ifndef ALU_OP_SV
`define ALU_OP_SV

typedef enum[2:0] {
    AluOpAdc,
    AluOpSbc,
    AluOpAnd,
    AluOpXor,
    AluOpOr,
    AluOpShiftL,
    AluOpShiftR
} alu_op_e;

`endif
