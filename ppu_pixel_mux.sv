`include "defs.svh"

module ppu_pixel_mux(
    input logic [3:0] bg_pal_idx_i,
    input logic       spr_priority_i [0:7],
    input logic [3:0] spr_pal_idx_i  [0:7],

    input slot_0_is_spr_0_i,
    output sprite_0_hit_o,

    input spr_enable_i,
    input bg_enable_i,

    output logic [4:0] color_o
);

logic [3:0] first_non_transparent_pixel;
logic first_non_transparent_pixel_priority;

always_comb begin : sprite_zero_hit_logic
    if (spr_enable_i && bg_enable_i && slot_0_is_spr_0_i &&
        spr_pal_idx_i[0][1:0] != 0 && bg_pal_idx_i[1:0] != 0
    ) begin
        sprite_0_hit_o = 1'h1;
    end else begin
        sprite_0_hit_o = 1'h0;
    end
end

int idx;
always_comb begin : sprite_pixel_logic
    first_non_transparent_pixel = '0;
    first_non_transparent_pixel_priority = '1;
    for (idx = 7; idx >= 0; idx = idx - 1) begin
        if (spr_pal_idx_i[idx][1:0] != 0) begin
            first_non_transparent_pixel = spr_pal_idx_i[idx];
            first_non_transparent_pixel_priority = spr_priority_i[idx];
        end
    end
end

always_comb begin : bg_spr_mux
    if (
        (!first_non_transparent_pixel_priority || bg_pal_idx_i[1:0] == 0) ||
        (first_non_transparent_pixel_priority && bg_pal_idx_i[1:0] == 0)
    ) begin
        color_o = {1'b1, first_non_transparent_pixel};
    end else begin
        color_o = {1'b0, bg_pal_idx_i};
    end
end

endmodule
