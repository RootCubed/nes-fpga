`include "defs.svh"

module ppu_oam(
    input logic clk,
    input logic rst_n,

    input  logic [7:0] addr_i,
    output logic [7:0] data_o,
    input  logic [7:0] data_i,
    input  logic       we_i
);

logic [7:0] oam_mem [0:255];

assign data_o = oam_mem[addr_i];

always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        oam_mem <= '{default:0};
    end else begin
        if (we_i) begin
            oam_mem[addr_i] <= data_i;
        end
    end
end

endmodule
