`timescale 1ns / 1ps

// Simple dual port RAM for a single scanline.

module VGALineBuffer (
    input [5:0] data_write,
    input [7:0] addr_read,
    input [7:0] addr_write,
    input we,
    input clk_read, clk_write,
    output reg [5:0] data_read
);

reg [5:0] ram[255:0];

always @ (posedge clk_write)
begin
    if (we) ram[addr_write] <= data_write;
end

always @ (posedge clk_read)
begin
    data_read <= ram[addr_read];
end

endmodule