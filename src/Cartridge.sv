`timescale 1ns / 1ps

// Module representing a game cartridge.
// TODO: Mappers
// TODO: Loading different carts without recompiling entire project

module Cartridge(
    input [14:0] addr_cpu,
    output reg [7:0] data_cpu,
    input [12:0] addr_ppu,
    output reg [7:0] data_ppu,
    input [7:0] data_ppu_write,
    input data_ppu_rw,
    input clk
);

reg [7:0] prg_rom [0:'h7FFF];
reg [7:0] chr_rom [0:'h1FFF];

initial begin
    $readmemh("data/prg_rom.mem", prg_rom);
    $readmemh("data/chr_rom.mem", chr_rom);
end

reg del_data_ppu_rw = 0;

always @ (negedge clk) begin
    del_data_ppu_rw <= data_ppu_rw;

    data_cpu <= prg_rom[addr_cpu];

    if (~data_ppu_rw & del_data_ppu_rw) begin
        //chr_rom[addr_ppu] <= data_ppu_write;
    end else begin
        data_ppu <= chr_rom[addr_ppu];
    end
end

endmodule