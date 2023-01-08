`include "defs.svh"

module ppu_palette(
    input logic clk,
    input logic rst_n,

    input  logic [4:0] addr_i,
    input  logic [7:0] data_i,
    output logic [7:0] data_o,
    input  logic       we_i
);

logic [7:0] pal_mem [0:31];

logic [4:0] true_addr;

always_comb begin : true_addr_logic
    if (addr_i[3:0] == 4'h0) begin
        true_addr = {1'b0, addr_i[3:0]};
    end else begin
        true_addr = addr_i;
    end
    data_o = pal_mem[true_addr];
end

always_ff @(posedge clk or negedge rst_n) begin
    if (we_i) begin
        pal_mem[true_addr] <= data_i;
    end
end

endmodule
