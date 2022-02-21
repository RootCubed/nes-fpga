`timescale 1ns / 1ps

// Generates the clock signals for the CPU, PPU and VGA output.

module ClockGen (
   input  wire clk_in,
   output wire clk_vga,
   output wire clk_mst
);

parameter CLKOUT0_DIVIDE = 31.625;
parameter CLKOUT1_DIVIDE = 37;
parameter CLKFBOUT_MULT  = 55.625;
parameter DIVCLK_DIVIDE  = 7;

wire clk_ibuf;
IBUF ibuf (
    .I(clk_in),
    .O(clk_ibuf)
);

wire clk_bufg;
BUFG bufg1 (
    .I(clk_ibuf),
    .O(clk_bufg)
);

// Feedback from CLKFBOUT to CLKFBIN
wire        FB_O;
wire        FB_I;

// Unbuffered output wires
wire clk0_out, clk1_out;

MMCME2_ADV #(
    .BANDWIDTH          ("OPTIMIZED"),
    .COMPENSATION       ("ZHOLD"),

    .CLKIN1_PERIOD      (10.0), // 10 ns = 100MHz
    .CLKIN2_PERIOD      (10.0),

    .CLKFBOUT_MULT_F    (CLKFBOUT_MULT),
    .CLKFBOUT_PHASE     (0),
    .DIVCLK_DIVIDE      (DIVCLK_DIVIDE),

    .CLKOUT0_DIVIDE_F   (CLKOUT0_DIVIDE),
    .CLKOUT0_DUTY_CYCLE (0.50),
    .CLKOUT0_PHASE      (0),
    .CLKOUT1_DIVIDE   (CLKOUT1_DIVIDE),
    .CLKOUT1_DUTY_CYCLE (0.50),
    .CLKOUT1_PHASE      (0),
    .STARTUP_WAIT       ("TRUE")
) pll (
    .CLKIN1     (clk_bufg),
    .CLKIN2     (clk_bufg),
    .CLKINSEL   (1'b1),

    .RST (1'b0),
    .PWRDWN(1'b0),

    .CLKFBIN    (FB_I),
    .CLKFBOUT   (FB_O),

    .CLKOUT0    (clk0_out),
    .CLKOUT1    (clk1_out)
);

assign FB_I = FB_O;

BUFG bufg2 (
    .I(clk0_out),
    .O(clk_vga)
);

BUFG bufg3 (
    .I(clk1_out),
    .O(clk_mst)
);

endmodule
