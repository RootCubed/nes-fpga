`include "defs.svh"

module ppu_sprite_store(
    input logic clk,
    input logic rst_n,

    input logic [8:0] x_i,

    input logic [7:0] data_i,
    input logic [1:0] data_type_i,
    input logic       data_we_i,

    output logic priority_o,
    
    output logic [3:0] spr_pal_idx_o
);

logic [7:0] x_counter;
logic [7:0] pattern_hi, pattern_lo;
logic [7:0] spr_attributes;

wire [1:0] palette = spr_attributes[1:0];
assign priority_o = spr_attributes[5];
wire flip_horiz = spr_attributes[6];

always_comb begin : calc_color
    if (x_counter == 0) begin
        if (flip_horiz) begin
            spr_pal_idx_o = {palette, pattern_hi[0], pattern_lo[0]};
        end else begin
            spr_pal_idx_o = {palette, pattern_hi[7], pattern_lo[7]};
        end
    end else begin
        spr_pal_idx_o = '0;
    end
end

always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        x_counter <= 8'hFF;
    end else begin
        if (data_we_i) begin
            case (data_type_i)
                0: spr_attributes <= data_i;
                1: x_counter <= data_i;
                2: pattern_lo <= data_i;
                3: pattern_hi <= data_i;
            endcase
        end else begin
            if (x_i < 256 && x_counter == 0) begin
                if (flip_horiz) begin
                    pattern_hi <= {1'b0, pattern_hi[7:1]};
                    pattern_lo <= {1'b0, pattern_lo[7:1]};
                end else begin
                    pattern_hi <= {pattern_hi[6:0], 1'b0};
                    pattern_lo <= {pattern_lo[6:0], 1'b0};
                end
            end else if (x_i < 256 && x_counter > 0) begin
                x_counter <= x_counter - 1;
            end
        end
    end
end

endmodule
