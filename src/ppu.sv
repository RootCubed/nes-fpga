`include "defs.svh"

module ppu(
    input logic clk,
    input logic rst_n,

    output logic [13:0] ppubus_address_o,
    input  logic [7:0] ppubus_data_i,
    output logic [7:0] ppubus_data_o,
    output logic ppubus_rw_o,

    input logic vram_ce,
    input logic vram_a10,
    
    input  logic [2:0] cpubus_address_i,
    input  logic [7:0] cpubus_data_i,
    output logic [7:0] cpubus_data_o,
    input  logic cpubus_rw_i,
    input  logic cpubus_ce_i,

    output logic nmi_o,

    output logic [4:0] color_o
);

// General PPU registers
logic [14:0] vram_home_addr_q, vram_home_addr_d; // Called t on Nesdev
logic [14:0] vram_addr_q, vram_addr_d; // Called v on Nesdev

logic [2:0] fine_x_q, fine_x_d;

logic [8:0] x_q, x_d, y_q, y_d;
`getter(x, x_q, [8:0]);
`getter(y, y_q, [8:0]);

logic spr_pattable_half_q, spr_pattable_half_d;
logic bg_pattable_half_q, bg_pattable_half_d;

// Primary OAM
logic [7:0] oam_addr;
logic [7:0] oam_data;
logic [7:0] oam_mmregs_addr;
logic [7:0] oam_write_data;
logic oam_we, oam_addr_w_o;

ppu_oam i_ppu_oam(
    .clk(clk),
    .rst_n(rst_n),
    .addr_i(oam_addr),
    .data_o(oam_data),
    .data_i(oam_write_data),
    .we_i(oam_we)
);

// Palette
logic [4:0] pal_addr;
logic [7:0] pal_data_r;
logic pal_we;

assign pal_addr = ppubus_address_o[4:0];
always_comb begin : palette_write_logic
    pal_we = (ppubus_address_o > 14'h3F00) && ppubus_rw_o;
end

ppu_palette i_ppu_palette(
    .clk(clk),
    .rst_n(rst_n),
    .addr_i(pal_addr),
    .data_i(ppubus_data_o),
    .data_o(pal_data_r),
    .we_i(pal_we)
);

logic [7:0] ppu_read_buffer;
logic [7:0] ppu_true_read_value;
logic [7:0] ppu_mmreg_true_read_value;

always_comb begin : ppu_read_value_logic
    if (ppubus_address_o >= 14'h3F00) begin
        ppu_true_read_value = pal_data_r;
        ppu_mmreg_true_read_value = pal_data_r;
    end else begin
        ppu_true_read_value = ppubus_data_i;
        ppu_mmreg_true_read_value = ppu_read_buffer;
    end
end

// Background registers
logic [7:0] curr_bg_tile_index_q, curr_bg_tile_index_d;

logic [7:0] tile_data_curr_hi_q, tile_data_curr_hi_d;
logic [7:0] tile_data_curr_lo_q, tile_data_curr_lo_d;
logic [1:0] attr_data_curr_q, attr_data_curr_d;

logic [15:0] tile_data_shiftreg_hi_q, tile_data_shiftreg_hi_d;
logic [15:0] tile_data_shiftreg_lo_q, tile_data_shiftreg_lo_d;
logic [15:0] attr_data_shiftreg_hi_q, attr_data_shiftreg_hi_d;
logic [15:0] attr_data_shiftreg_lo_q, attr_data_shiftreg_lo_d;

logic [3:0] bg_pal_idx;

logic [13:0] bg_vram_addr, spr_vram_addr;

ppu_bg_control i_ppu_bg_control(
    .x_i(x_q),

    .vram_addr_i(vram_addr_q),
    .fine_x_i(fine_x_q),

    .curr_bg_tile_index_i(curr_bg_tile_index_q),
    .curr_bg_tile_index_o(curr_bg_tile_index_d),

    .tile_data_shiftreg_hi_i(tile_data_shiftreg_hi_q),
    .tile_data_shiftreg_hi_o(tile_data_shiftreg_hi_d),
    .tile_data_shiftreg_lo_i(tile_data_shiftreg_lo_q),
    .tile_data_shiftreg_lo_o(tile_data_shiftreg_lo_d),

    .attr_data_curr_i(attr_data_curr_q),
    .attr_data_curr_o(attr_data_curr_d),

    .tile_data_curr_hi_i(tile_data_curr_hi_q),
    .tile_data_curr_hi_o(tile_data_curr_hi_d),
    .tile_data_curr_lo_i(tile_data_curr_lo_q),
    .tile_data_curr_lo_o(tile_data_curr_lo_d),

    .attr_data_shiftreg_hi_i(attr_data_shiftreg_hi_q),
    .attr_data_shiftreg_hi_o(attr_data_shiftreg_hi_d),
    .attr_data_shiftreg_lo_i(attr_data_shiftreg_lo_q),
    .attr_data_shiftreg_lo_o(attr_data_shiftreg_lo_d),

    .bg_pal_idx_o(bg_pal_idx),

    .bg_pattable_half_i(bg_pattable_half_q),
    .ppubus_addr_o(bg_vram_addr),
    .ppubus_data_i(ppu_true_read_value)
);

// Sprite registers
logic [7:0] sprite_store_data;
logic [1:0] sprite_store_data_type;
wire [2:0] sprite_store_select_index;
logic sprite_store_we;

logic [7:0] sprite_store_select = 1 << sprite_store_select_index;

logic spr_priority [0:7];
logic [3:0] spr_pal_idx [0:7];

logic [7:0] curr_spr_y_pos_q, curr_spr_y_pos_d;
logic [7:0] curr_spr_tile_index_q, curr_spr_tile_index_d;
logic curr_spr_is_flip_vert_q, curr_spr_is_flip_vert_d;

logic [4:0] sec_oam_addr;
logic [7:0] sec_oam_data;

logic sprite_overflow;
logic sprite_0_hit;
logic slot_0_is_spr_0;

genvar i;
generate
    for (i = 0; i < 8; i = i + 1) begin
        ppu_sprite_store i_ppu_sprite_store(
            .clk(clk),
            .rst_n(rst_n),

            .x_i(x_q),

            .data_i(sprite_store_data),
            .data_type_i(sprite_store_data_type),
            .data_we_i(sprite_store_select[i] & sprite_store_we),
            
            .priority_o(spr_priority[i]),

            .spr_pal_idx_o(spr_pal_idx[i])
        );
    end
endgenerate

ppu_sprite_control i_ppu_sprite_control(
    .x_i(x_q),
    .y_i(y_q),

    .sprite_store_data_o(sprite_store_data),
    .sprite_store_data_type_o(sprite_store_data_type),
    .sprite_store_select_index_o(sprite_store_select_index),
    .sprite_store_we_o(sprite_store_we),
    
    .curr_spr_y_pos_i(curr_spr_y_pos_q),
    .curr_spr_y_pos_o(curr_spr_y_pos_d),
    .curr_spr_tile_index_i(curr_spr_tile_index_q),
    .curr_spr_tile_index_o(curr_spr_tile_index_d),
    .curr_spr_is_flip_vert_i(curr_spr_is_flip_vert_q),
    .curr_spr_is_flip_vert_o(curr_spr_is_flip_vert_d),

    .sec_oam_addr_o(sec_oam_addr),
    .sec_oam_data_i(sec_oam_data),

    .ppubus_addr_o(spr_vram_addr),
    .ppubus_data_i(ppu_true_read_value),

    .sprite_pattable_half_i(spr_pattable_half_q)
);

ppu_sprite_eval i_ppu_sprite_eval(
    .clk(clk),
    .rst_n(rst_n),

    .x_i(x_q),
    .y_i(y_q),

    .spr_enable_i(spr_enable),

    .oam_addr_o(oam_addr),
    .oam_data_i(oam_data),

    .new_oam_addr_i(oam_mmregs_addr),
    .new_oam_addr_w_i(oam_addr_w_o),

    .sec_oam_addr_i(sec_oam_addr),
    .sec_oam_data_o(sec_oam_data),

    .overflow_o(sprite_overflow),
    .slot_0_is_spr_0_o(slot_0_is_spr_0)
);

ppu_pixel_mux i_ppu_pixel_mux(
    .bg_pal_idx_i(bg_pal_idx),
    .spr_priority_i(spr_priority),
    .spr_pal_idx_i(spr_pal_idx),

    .slot_0_is_spr_0_i(slot_0_is_spr_0),
    .sprite_0_hit_o(sprite_0_hit),
    
    .spr_enable_i(spr_enable),
    .bg_enable_i(bg_enable),

    .color_o(color_o)
);

logic [14:0] vram_home_addr_mmregset;
logic vram_home_we_mmregset;
logic reset_vram_to_home;
logic [2:0] fine_x_mmregset;
logic fine_x_we_mmregset;

logic inc_vram_1, inc_vram_32;
logic bg_enable, spr_enable;

logic mmregs_override_addr;

ppu_mmregs i_ppu_mmregs(
    .clk(clk),
    .rst_n(rst_n),

    .x_i(x_q),
    .y_i(y_q),

    .addr_i(cpubus_address_i),
    .data_i(cpubus_data_i),
    .we_i(cpubus_rw_i),
    .ce_i(cpubus_ce_i),
    .data_o(cpubus_data_o),
    
    .nmi_o(nmi_o),

    .oam_data_i(oam_data),
    .oam_addr_i(oam_addr),
    .oam_addr_o(oam_mmregs_addr),
    .oam_addr_w_o(oam_addr_w_o),
    .oam_data_o(oam_write_data),
    .oam_data_w_o(oam_we),

    .sprite_overflow_i(sprite_overflow),
    .sprite_0_hit_i(sprite_0_hit),
    
    .spr_pattable_half_o(spr_pattable_half_d),
    .bg_pattable_half_o(bg_pattable_half_d),
    .bg_enable_o(bg_enable),
    .spr_enable_o(spr_enable),

    .vram_data_i(ppu_mmreg_true_read_value),
    .vram_data_o(ppubus_data_o),
    .vram_override_addr_o(mmregs_override_addr),
    .vram_we_o(ppubus_rw_o),

    .vram_home_addr_i(vram_home_addr_q),
    .vram_home_addr_o(vram_home_addr_mmregset),
    .vram_home_addr_we_o(vram_home_we_mmregset),
    .reset_vram_to_home_o(reset_vram_to_home),
    .inc_vram_1_o(inc_vram_1),
    .inc_vram_32_o(inc_vram_32),

    .fine_x_o(fine_x_mmregset),
    .fine_x_we_o(fine_x_we_mmregset)
);

logic odd_frame_q, odd_frame_d;
logic [14:0] vram_addr_ppu_control;

ppu_control i_ppu_control(
    .x_i(x_q),
    .x_o(x_d),
    .y_i(y_q),
    .y_o(y_d),

    .rendering_enabled_i(bg_enable || spr_enable),
    
    .odd_frame_i(odd_frame_q),
    .odd_frame_o(odd_frame_d),

    .vram_home_addr_i(vram_home_addr_q),
    .vram_addr_i(vram_addr_q),
    .vram_addr_o(vram_addr_ppu_control)
);

always_comb begin : next_vram_addr_logic
    vram_home_addr_d = vram_home_addr_q;
    if (bg_enable || spr_enable) begin
        vram_addr_d = vram_addr_ppu_control;
    end else begin
        vram_addr_d = vram_addr_q;
    end
    fine_x_d = fine_x_q;

    if (vram_home_we_mmregset) vram_home_addr_d = vram_home_addr_mmregset;

    if (reset_vram_to_home) vram_addr_d = vram_home_addr_mmregset;
    if (inc_vram_1) vram_addr_d = vram_addr_q + 15'd1;
    if (inc_vram_32) vram_addr_d = vram_addr_q + 15'd32;

    if (fine_x_we_mmregset) fine_x_d = fine_x_mmregset;
end

always_comb begin : vram_fetch_addr
    if (mmregs_override_addr) begin
        ppubus_address_o = vram_addr_q[13:0];
    end else begin
        if (x_q > 9'd256 && x_q < 9'd320) begin
            ppubus_address_o = spr_vram_addr;
        end else begin
            ppubus_address_o = bg_vram_addr;
        end
    end
end

always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        vram_home_addr_q <= '0;
        vram_addr_q <= '0;
        fine_x_q <= '0;
        x_q <= 9'd322; // Needed to match Nintendulator output
        y_q <= 9'd261;
        odd_frame_q <= '0;
        ppu_read_buffer <= '0;

        spr_pattable_half_q <= '0;
        bg_pattable_half_q <= '0;
        curr_bg_tile_index_q <= '0;

        tile_data_curr_hi_q <= '0;
        tile_data_curr_lo_q <= '0;
        attr_data_curr_q <= '0;

        tile_data_shiftreg_hi_q <= '0;
        tile_data_shiftreg_lo_q <= '0;
        attr_data_shiftreg_hi_q <= '0;
        attr_data_shiftreg_lo_q <= '0;
    end else begin
        vram_home_addr_q <= vram_home_addr_d;
        vram_addr_q <= vram_addr_d;

        ppu_read_buffer <= ppubus_data_i;

        fine_x_q <= fine_x_d;
        x_q <= x_d;
        y_q <= y_d;
        odd_frame_q <= odd_frame_d;

        if (x_q < 9'd336) begin

            spr_pattable_half_q <= spr_pattable_half_d;
            bg_pattable_half_q <= bg_pattable_half_d;
            curr_bg_tile_index_q <= curr_bg_tile_index_d;

            tile_data_curr_hi_q <= tile_data_curr_hi_d;
            tile_data_curr_lo_q <= tile_data_curr_lo_d;
            attr_data_curr_q <= attr_data_curr_d;

            tile_data_shiftreg_hi_q <= tile_data_shiftreg_hi_d;
            tile_data_shiftreg_lo_q <= tile_data_shiftreg_lo_d;
            attr_data_shiftreg_hi_q <= attr_data_shiftreg_hi_d;
            attr_data_shiftreg_lo_q <= attr_data_shiftreg_lo_d;
            
            curr_spr_y_pos_q <= curr_spr_y_pos_d;
            curr_spr_tile_index_q <= curr_spr_tile_index_d;
            curr_spr_is_flip_vert_q <= curr_spr_is_flip_vert_d;
        end
    end
end

endmodule
