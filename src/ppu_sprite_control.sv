`include "defs.svh"

module ppu_sprite_control(
    input logic [8:0] x_i,
    input logic [8:0] y_i,

    output logic [7:0] sprite_store_data_o,
    output logic [1:0] sprite_store_data_type_o,
    output logic [2:0] sprite_store_select_index_o,
    output logic       sprite_store_we_o,
    
    input  logic [7:0] curr_spr_y_pos_i,
    output logic [7:0] curr_spr_y_pos_o,
    input  logic [7:0] curr_spr_tile_index_i,
    output logic [7:0] curr_spr_tile_index_o,
    input  logic curr_spr_is_flip_vert_i,
    output logic curr_spr_is_flip_vert_o,

    output logic [4:0] sec_oam_addr_o,
    input  logic [7:0] sec_oam_data_i,

    output logic [13:0] ppubus_addr_o,
    input  logic  [7:0] ppubus_data_i,

    input logic sprite_pattable_half_i
);

wire [2:0] curr_phase = x_i[2:0];

logic [13:0] tilelo_addr, tilehi_addr;
logic [8:0] actual_y_offset;

always_comb begin : sprite_select
    sprite_store_select_index_o = x_i[5:3];
end

always_comb begin : vram_addr_logic
    if (curr_spr_is_flip_vert_i) begin
        actual_y_offset = 9'd7 - (y_i - curr_spr_y_pos_i);
    end else begin
        actual_y_offset = y_i - curr_spr_y_pos_i;
    end
    tilelo_addr = {1'b0, sprite_pattable_half_i, curr_spr_tile_index_i, 1'b0, actual_y_offset[2:0]};
    tilehi_addr = {1'b0, sprite_pattable_half_i, curr_spr_tile_index_i, 1'b1, actual_y_offset[2:0]};

    case (curr_phase)
        4, 5: ppubus_addr_o = tilelo_addr;
        6, 7: ppubus_addr_o = tilehi_addr;
        default: ppubus_addr_o = '0;
    endcase
end

always_comb begin : sec_oam_addr_logic
    case (curr_phase)
        0, 1, 2, 3: sec_oam_addr_o = {x_i[5:3], x_i[1:0]};
        default: sec_oam_addr_o = '0;
    endcase
end

always_comb begin : sprite_attributes_save_logic
    curr_spr_y_pos_o = curr_spr_y_pos_i;
    curr_spr_tile_index_o = curr_spr_tile_index_i;
    curr_spr_is_flip_vert_o = curr_spr_is_flip_vert_i;
    if (curr_phase == 0) begin
        curr_spr_y_pos_o = sec_oam_data_i;
    end
    if (curr_phase == 1) begin
        curr_spr_tile_index_o = sec_oam_data_i;
    end
    if (curr_phase == 2) begin
        curr_spr_is_flip_vert_o = sec_oam_data_i[7];
    end
end

always_comb begin : sprite_store_logic
    case (curr_phase)
        0: sprite_store_data_o = sec_oam_data_i;
        1: sprite_store_data_o = sec_oam_data_i;
        2: sprite_store_data_o = sec_oam_data_i;
        3: sprite_store_data_o = sec_oam_data_i;
        5, 7: sprite_store_data_o = ppubus_data_i;
    endcase

    case (curr_phase)
        2: sprite_store_data_type_o = 2'd0;
        3: sprite_store_data_type_o = 2'd1;
        5: sprite_store_data_type_o = 2'd2;
        7: sprite_store_data_type_o = 2'd3;
        default: sprite_store_data_type_o = 2'd0;
    endcase

    if (x_i > 256 && x_i <= 320) begin
        case (curr_phase)
            2, 3, 5, 7: sprite_store_we_o = '1;
            default: sprite_store_we_o = '0;
        endcase
    end else begin
        sprite_store_we_o = '0;
    end
end

endmodule
