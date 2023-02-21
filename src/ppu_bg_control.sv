`include "defs.svh"

module ppu_bg_control(
    input logic [8:0] x_i,

    input logic [14:0] vram_addr_i,
    input logic [2:0] fine_x_i,

    input  logic [7:0] curr_bg_tile_index_i,
    output logic [7:0] curr_bg_tile_index_o,

    input  logic [7:0] tile_data_curr_hi_i,
    output logic [7:0] tile_data_curr_hi_o,
    input  logic [7:0] tile_data_curr_lo_i,
    output logic [7:0] tile_data_curr_lo_o,
    
    input  logic [1:0] attr_data_curr_i,
    output logic [1:0] attr_data_curr_o,

    input  logic [15:0] tile_data_shiftreg_hi_i,
    output logic [15:0] tile_data_shiftreg_hi_o,
    input  logic [15:0] tile_data_shiftreg_lo_i,
    output logic [15:0] tile_data_shiftreg_lo_o,

    input  logic [15:0] attr_data_shiftreg_hi_i,
    output logic [15:0] attr_data_shiftreg_hi_o,
    input  logic [15:0] attr_data_shiftreg_lo_i,
    output logic [15:0] attr_data_shiftreg_lo_o,

    output logic [3:0] bg_pal_idx_o,

    input logic bg_pattable_half_i,

    output logic [13:0] ppubus_addr_o,
    input  logic  [7:0] ppubus_data_i
);

wire [2:0] curr_phase = x_i[2:0];

wire [2:0] fine_y = vram_addr_i[14:12];
wire [1:0] nametable_sel = vram_addr_i[11:10];
wire [4:0] coarse_y = vram_addr_i[9:5];
wire [4:0] coarse_x = vram_addr_i[4:0];

logic [13:0] nametable_addr, attrtable_addr, tilelo_addr, tilehi_addr;

always_comb begin : fetch_addr_logic
    nametable_addr = {2'b10, vram_addr_i[11:0]};
    attrtable_addr = {2'b10, nametable_sel, 4'b1111, coarse_y[4:2], coarse_x[4:2]};
    tilelo_addr = {1'b0, bg_pattable_half_i, curr_bg_tile_index_i, 1'b0, fine_y};
    tilehi_addr = {1'b0, bg_pattable_half_i, curr_bg_tile_index_i, 1'b1, fine_y};

    case (curr_phase)
        0, 1: ppubus_addr_o = nametable_addr;
        2, 3: ppubus_addr_o = attrtable_addr;
        4, 5: ppubus_addr_o = tilelo_addr;
        6, 7: ppubus_addr_o = tilehi_addr;
    endcase
end

always_comb begin : nt_byte_save_logic
    curr_bg_tile_index_o = (curr_phase == 1) ? ppubus_data_i : curr_bg_tile_index_i;
end
always_comb begin : attr_save_logic
    attr_data_curr_o = attr_data_curr_i;
    if (curr_phase == 3) begin
        case ({coarse_y[1], coarse_x[1]})
            2'b00: attr_data_curr_o = ppubus_data_i[1:0];
            2'b01: attr_data_curr_o = ppubus_data_i[3:2];
            2'b10: attr_data_curr_o = ppubus_data_i[5:4];
            2'b11: attr_data_curr_o = ppubus_data_i[7:6];
        endcase
    end
end
always_comb begin : pattern_save_logic
    tile_data_curr_hi_o = (curr_phase == 5) ? ppubus_data_i : tile_data_curr_hi_i;
    tile_data_curr_lo_o = (curr_phase == 7) ? ppubus_data_i : tile_data_curr_lo_i;
end

always_comb begin : shift_reg_logic
    if (curr_phase == 0) begin
        tile_data_shiftreg_hi_o = {1'b0, {<<{tile_data_curr_hi_i}}, tile_data_shiftreg_hi_i[7:1]};
        tile_data_shiftreg_lo_o = {1'b0, {<<{tile_data_curr_lo_i}}, tile_data_shiftreg_lo_i[7:1]};
        attr_data_shiftreg_hi_o = {1'b0, {8{attr_data_curr_i[1]}}, attr_data_shiftreg_hi_i[7:1]};
        attr_data_shiftreg_lo_o = {1'b0, {8{attr_data_curr_i[0]}}, attr_data_shiftreg_lo_i[7:1]};
    end else begin
        tile_data_shiftreg_hi_o = {1'b0, tile_data_shiftreg_hi_i[15:1]};
        tile_data_shiftreg_lo_o = {1'b0, tile_data_shiftreg_lo_i[15:1]};
        attr_data_shiftreg_hi_o = {1'b0, attr_data_shiftreg_hi_i[15:1]};
        attr_data_shiftreg_lo_o = {1'b0, attr_data_shiftreg_lo_i[15:1]};
    end
end

always_comb begin : pixel_calc_logic
    logic [3:0] sel = {1'b0, fine_x_i};
    bg_pal_idx_o = {
        attr_data_shiftreg_hi_i[sel], attr_data_shiftreg_lo_i[sel],
        tile_data_shiftreg_lo_i[sel], tile_data_shiftreg_hi_i[sel]
    };
end

endmodule
