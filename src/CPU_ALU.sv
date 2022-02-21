`timescale 1ns / 1ps

// ALU unit for the CPU.

module CPU_ALU(
    input [7:0] in_a,
    input [7:0] in_b,
    input [2:0] aluop,
    input carry_in,
    output [7:0] out,
    output overflow,
    output carry_out
);

// operations:
// 0: add
// 1: sub
// 2: and
// 3: xor
// 4: or
// 5: shr
// 6: shl

wire [8:0] tmp_adc = in_a + in_b + {7'b0, carry_in};
wire [8:0] tmp_sbc = in_a - in_b - {7'b0, !carry_in};

assign out =
    (aluop == 3'd0) ? tmp_adc[7:0] :
    (aluop == 3'd1) ? tmp_sbc[7:0] :
    (aluop == 3'd2) ? in_a & in_b :
    (aluop == 3'd3) ? in_a ^ in_b :
    (aluop == 3'd4) ? in_a | in_b :
    (aluop == 3'd5) ? {carry_in, in_a[7:1]} :
    (aluop == 3'd6) ? {in_a[6:0], carry_in} : 0;

assign overflow =
    (aluop == 3'd0) ? ((in_a ^ out) & (in_b ^ out) & 'h80) == 'h80 :
    (aluop == 3'd1) ? ((in_a ^ out) & (('hFF - in_b) ^ out) & 'h80) == 'h80 : 0;

assign carry_out =
    (aluop == 3'd0) ? tmp_adc[8] :
    (aluop == 3'd1) ? !tmp_sbc[8] :
    (aluop == 3'd5) ? in_a[0] :
    (aluop == 3'd6) ? in_a[7] : 0;

endmodule
