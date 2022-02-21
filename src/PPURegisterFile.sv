`timescale 1ns / 1ps

// Module for the CPU-facing PPU registers and the internal palette.

module PPURegisterFile(
    input master_clk,
    input rst,
    input [2:0] address,
    input [7:0] din,
    output reg [7:0] dout = 0,
    input cpu_rw,
    input cpu_rw_active,

    input [4:0] palette_addr,
    output [5:0] palette_data,
    output [5:0] palette_bg,

    input [4:0] palette_sp0_addr,
    output [5:0] palette_sp0_data,
    input [4:0] palette_sp1_addr,
    output [5:0] palette_sp1_data,
    input [4:0] palette_sp2_addr,
    output [5:0] palette_sp2_data,
    input [4:0] palette_sp3_addr,
    output [5:0] palette_sp3_data,
    input [4:0] palette_sp4_addr,
    output [5:0] palette_sp4_data,
    input [4:0] palette_sp5_addr,
    output [5:0] palette_sp5_data,
    input [4:0] palette_sp6_addr,
    output [5:0] palette_sp6_data,
    input [4:0] palette_sp7_addr,
    output [5:0] palette_sp7_data,

    input inc_coarse_x,
    input inc_fine_y,
    input inc_oam_addr,
    input reset_coarse_x,
    input reset_v,
    input [1:0] set_vblank,
    input [1:0] set_sprite_overflow,
    input reset_oam_addr,
    input set_sprite_zero_hit,

    output reg [2:0] v_fine_y = 0,
    output reg [1:0] v_nt_sel = 0,
    output reg [4:0] v_coarse_y = 0,
    output reg [4:0] v_coarse_x = 0,
    output reg [2:0] fine_x = 0,

    output [7:0] PPUCTRL,
    output [7:0] PPUSTATUS,
    output [7:0] PPUMASK,
    output reg nmi_occurred = 0,

    output reg [7:0] oam_addr = 0,

    output reg [13:0] addressbus = 0,
    output reg mem_rw_active = 0,
    output reg mem_write_active = 0,
    output reg [7:0] mem_write_data = 0,
    input [7:0] data_read
);

// Palette is connected directly to the PPU
reg [7:0] palette [0:'h1F];
integer i;
initial begin
    for(i = 0; i < 'h1F; i = i + 1) begin
        palette[i] = 8'b0;
    end
end

assign palette_data = palette[palette_addr][5:0];
assign palette_bg = palette[0][5:0];

assign palette_sp0_data = palette[palette_sp0_addr][5:0];
assign palette_sp1_data = palette[palette_sp1_addr][5:0];
assign palette_sp2_data = palette[palette_sp2_addr][5:0];
assign palette_sp3_data = palette[palette_sp3_addr][5:0];
assign palette_sp4_data = palette[palette_sp4_addr][5:0];
assign palette_sp5_data = palette[palette_sp5_addr][5:0];
assign palette_sp6_data = palette[palette_sp6_addr][5:0];
assign palette_sp7_data = palette[palette_sp7_addr][5:0];

// PPUCTRL
reg gen_nmi = 0;
reg master_slave_select = 0;
reg sprite_size = 0;
reg bg_pattern_table = 0;
reg sprite_pattern_table = 0;
reg vram_inc = 0;

// PPUMASK
reg emph_blue = 0;
reg emph_green = 0;
reg emph_red = 0;
reg show_sprites = 0;
reg show_bg = 0;
reg show_left_sprites = 0;
reg show_left_bg = 0;
reg grayscale = 0;

// PPUSTATUS
reg sprite_zero_hit = 0;
reg sprite_overflow = 0;

// CPU communication
reg ppu_first_write = 1;
reg [7:0] mem_read_buffer = 0;

// Data loading

reg [2:0] t_fine_y = 0;
reg [1:0] t_nt_sel = 0;
reg [4:0] t_coarse_y = 0;
reg [4:0] t_coarse_x = 0;

wire [14:0] vram_addr     = {v_fine_y, v_nt_sel, v_coarse_y, v_coarse_x};
wire [14:0] tmp_vram_addr = {t_fine_y, t_nt_sel, t_coarse_y, t_coarse_x};

assign PPUCTRL = {gen_nmi, master_slave_select, sprite_size, bg_pattern_table, sprite_pattern_table, vram_inc, t_nt_sel};
assign PPUSTATUS = {nmi_occurred, sprite_zero_hit, sprite_overflow, 5'h0};
assign PPUMASK = {
    emph_blue, emph_green, emph_red,
    show_sprites, show_bg,
    show_left_sprites, show_left_bg,
    grayscale
};

reg did_reg_access = 0;

reg wait_for_stop_access = 0;

reg del_inc_coarse_x = 0;
reg del_inc_fine_y = 0;
reg del_inc_oam_addr = 0;
reg del_reset_coarse_x = 0;
reg del_reset_v = 0;
reg del_reset_oam_addr = 0;
reg del_set_sprite_zero_hit = 0;

reg [3:0] delay_mem_read = 0;

always @ (posedge master_clk)
begin
    if (rst) begin
        // TODO: PPU reset behaviour
    end

    del_inc_coarse_x <= inc_coarse_x;
    del_inc_fine_y <= inc_fine_y;
    del_inc_oam_addr <= inc_oam_addr;
    del_reset_coarse_x <= reset_coarse_x;
    del_reset_v <= reset_v;
    del_reset_oam_addr <= reset_oam_addr;
    del_set_sprite_zero_hit <= set_sprite_zero_hit;

    if (inc_coarse_x & ~del_inc_coarse_x) v_coarse_x <= v_coarse_x + 1;
    if (reset_coarse_x & ~del_reset_coarse_x) v_coarse_x <= t_coarse_x;
    if (inc_fine_y & ~del_inc_fine_y) begin
        if (v_fine_y == 3'b111) begin
            v_fine_y <= 0;
            v_coarse_y <= v_coarse_y + 1;
        end else begin
            v_fine_y <= v_fine_y + 1;
        end
    end
    if (reset_v & ~del_reset_v) begin
        v_fine_y <= t_fine_y;
        v_nt_sel <= t_nt_sel;
        v_coarse_y <= t_coarse_y;
        v_coarse_x <= t_coarse_x;
    end
    if (set_vblank == 1) begin
        nmi_occurred <= 1;
    end
    if (set_vblank == 2) begin
        nmi_occurred <= 0;
        sprite_zero_hit <= 0;
    end

    if (set_sprite_overflow == 1) begin
        sprite_overflow <= 1;
    end
    if (set_sprite_overflow == 2) begin
        sprite_overflow <= 0;
    end

    if (reset_oam_addr & ~del_reset_oam_addr) begin
        oam_addr <= 0;
    end

    if (inc_oam_addr & ~del_inc_oam_addr) begin
        oam_addr <= oam_addr + 1;
    end

    if (set_sprite_zero_hit & ~del_set_sprite_zero_hit) begin
        sprite_zero_hit <= 1;
    end

    if (!cpu_rw_active) begin
        wait_for_stop_access <= 0;
        mem_rw_active <= 0;
    end
    if (did_reg_access) begin
        if (delay_mem_read == 0) begin
            mem_read_buffer <= data_read;
            {v_fine_y, v_nt_sel, v_coarse_y, v_coarse_x} <= {v_fine_y, v_nt_sel, v_coarse_y, v_coarse_x} + ((!vram_inc) ? 1 : 32);
            did_reg_access <= 0;
        end else begin
            delay_mem_read <= delay_mem_read - 1;
        end
    end else begin
        // CPU communication
        if (cpu_rw_active) begin
            if (!wait_for_stop_access) begin
                wait_for_stop_access <= 1;
                if (cpu_rw) begin
                    // read
                    case (address)
                        'h2: begin
                            dout[7:5] <= PPUSTATUS[7:5];
                            nmi_occurred <= 0;
                            ppu_first_write <= 1;
                        end
                        'h7: begin
                            if (vram_addr >= 'h3000) begin
                                if (vram_addr < 'h3f10 || (vram_addr & 'h3) != 0) begin
                                    dout <= palette[vram_addr[4:0]];
                                    mem_read_buffer <= palette[vram_addr[4:0]];
                                end else begin
                                    // 0x3F10, 0x3F14, 0x3F18 and 0x3F1C are mirrors
                                    dout <= palette[{1'b0, vram_addr[3:0]}];
                                    mem_read_buffer <= palette[{1'b0, vram_addr[3:0]}];
                                end
                            end else begin
                                dout <= mem_read_buffer;
                            end
                            addressbus <= vram_addr[13:0];
                            mem_rw_active <= 1;
                            mem_write_active <= 0;
                            did_reg_access <= 1;
                            // TODO: this is a really hacky solution but I guess it works for now
                            delay_mem_read <= 10;
                        end
                        default: ;
                    endcase
                end else begin
                    // write
                    dout <= din;
                    case (address)
                        'h0: begin
                            {
                                gen_nmi,
                                master_slave_select,
                                sprite_size,
                                bg_pattern_table,
                                sprite_pattern_table,
                                vram_inc,
                                t_nt_sel
                            } <= din;
                        end
                        'h1: begin
                            {
                                emph_blue,
                                emph_green,
                                emph_red,
                                show_sprites,
                                show_bg,
                                show_left_sprites,
                                show_left_bg,
                                grayscale
                            } <= din;
                        end
                        'h3: begin
                            oam_addr <= din;
                        end
                        'h5: begin
                            if (ppu_first_write) begin
                                {t_coarse_x, fine_x} <= din;
                            end else begin
                                {t_coarse_y, t_fine_y} <= din;
                            end
                            ppu_first_write <= !ppu_first_write;
                        end
                        'h6: begin
                            if (ppu_first_write) begin
                                v_coarse_y[2] <= 0;
                                {v_fine_y[1:0], v_nt_sel, v_coarse_y[4:3]} <= din[5:0];
                            end else begin
                                {v_coarse_y[2:0], v_coarse_x} <= din;
                            end
                            ppu_first_write <= !ppu_first_write;
                        end
                        'h7: begin
                            if (vram_addr >= 'h3000) begin
                                if (vram_addr < 'h3f10 || (vram_addr & 'h3) != 0) begin
                                    palette[vram_addr[4:0]] <= din;
                                end else begin
                                    // 0x3F10, 0x3F14, 0x3F18 and 0x3F1C are mirrors
                                    palette[{1'b0, vram_addr[3:0]}] <= din;
                                end
                            end else begin
                                addressbus <= vram_addr[13:0];
                                mem_rw_active <= 1;
                                mem_write_active <= 1;
                                mem_write_data <= din;
                            end
                            {v_fine_y, v_nt_sel, v_coarse_y, v_coarse_x} <= {v_fine_y, v_nt_sel, v_coarse_y, v_coarse_x} + ((!vram_inc) ? 1 : 32);
                        end
                        default: ;
                    endcase
                end
            end
        end
    end
end
endmodule

