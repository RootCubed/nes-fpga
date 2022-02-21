`timescale 1ns / 1ps

// Top-level module.

module NES(
    input clk,
    output [3:0] red,
    output [3:0] grn,
    output [3:0] blu,
    output hsync,
    output vsync,
    input reset,
    output [7:0] sevenseg,
    output [3:0] sevenseg_ac,
    input [7:0] ctrl1
);

wire clkMaster; // phi0 signal, double the speed of the actual clock
wire clkVGA;
ClockGen clock_generator(
    .clk_in(clk),
    .clk_vga(clkVGA),
    .clk_mst(clkMaster)
);

NESMain nes(
    .clkMaster(clkMaster),
    .clkVGA(clkVGA),
    .rgb_out({red, grn, blu}),
    .hsync(hsync),
    .vsync(vsync),
    .rst(reset),
    .ctrl1(ctrl1)
);

DebugOutput dbg(
    .clk(clkMaster),
    .number_in(nes.cpu.pc),
    .sevenseg_out(sevenseg),
    .sevseg_active(sevenseg_ac)
);

endmodule
