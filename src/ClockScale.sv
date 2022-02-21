`timescale 1ns / 1ps

// Scales the master clock for the CPU and PPU.
// TODO: is clk_data really needed?

module ClockScale(
    input clk_in,
    output reg clk_cpu = 1,
    output reg clk_ppu = 1,
    output reg clk_data = 1
);

reg [3:0] countCPU = 0;
reg [3:0] countData = 0;
reg [3:0] countPPU = 0;

always @ (posedge clk_in)
begin
    if (countData == 2) begin
        countData <= 0;
        clk_data <= !clk_data;
    end else begin
        countData <= countData + 1;
    end

    if (countCPU == 5) begin
        countCPU <= 0;
        clk_cpu <= !clk_cpu;
    end else begin
        countCPU <= countCPU + 1;
    end

    if (countPPU == 1) begin
        countPPU <= 0;
        clk_ppu <= !clk_ppu;
    end else begin
        countPPU <= countPPU + 1;
    end
end

endmodule
