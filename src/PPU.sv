`timescale 1ns / 1ps

// NES PPU module

module PPU(
    input master_clk,
    input clk,
    input clkData,
    input clkVGA,

    output [13:0] internal_mem_addr,
    input [7:0] internal_mem_din,
    output reg [7:0] internal_mem_dout = 0,
    output reg internal_mem_rw = 1,

    input [2:0] cpu_a,
    input [7:0] cpu_din,
    output [7:0] cpu_dout,

    input cpu_rw_active,
    input cpu_rw,

    input cpu_oam_dma_active,

    output nmi,
    input rst,
    output hsync,
    output vsync,
    output [3:0] red,
    output [3:0] grn,
    output [3:0] blu
);

parameter SCANLINE_COUNT = 262;
parameter CYCLE_COUNT    = 341;

// PPU registers / CPU communication

reg inc_coarse_x = 0;
reg inc_fine_y = 0;
reg reset_coarse_x = 0;
reg reset_v = 0;
reg [1:0] set_vblank = 0;
reg [1:0] set_sprite_overflow = 0;
reg reset_oam_addr = 0;
reg set_sprite_zero_hit = 0;

wire [13:0] reg_addressbus; // for registers that access memory
wire mem_write_active;
wire [7:0] data_write;
wire reg_addressbus_active;
wire [7:0] dataline;

wire [4:0] palette_addr;
wire [5:0] palette_data;
wire [5:0] bg_color;

wire [4:0] palette_sp0_addr;
wire [5:0] palette_sp0_data;
wire [4:0] palette_sp1_addr;
wire [5:0] palette_sp1_data;
wire [4:0] palette_sp2_addr;
wire [5:0] palette_sp2_data;
wire [4:0] palette_sp3_addr;
wire [5:0] palette_sp3_data;
wire [4:0] palette_sp4_addr;
wire [5:0] palette_sp4_data;
wire [4:0] palette_sp5_addr;
wire [5:0] palette_sp5_data;
wire [4:0] palette_sp6_addr;
wire [5:0] palette_sp6_data;
wire [4:0] palette_sp7_addr;
wire [5:0] palette_sp7_data;

wire [2:0] v_fine_y;
wire [1:0] v_nt_sel;
wire [4:0] v_coarse_y;
wire [4:0] v_coarse_x;
wire [2:0] fine_x;

wire [7:0] PPUCTRL;
wire [7:0] PPUSTATUS;
wire [7:0] PPUMASK;

wire nmi_occurred;

wire [7:0] oam_addr;

reg dma_did_write = 0;

PPURegisterFile regs(
    .master_clk,
    .rst,
    .address(cpu_a),
    .din(cpu_din),
    .dout(cpu_dout),
    .cpu_rw,
    .cpu_rw_active,

    .palette_addr,
    .palette_data,
    .palette_bg(bg_color),

    .palette_sp0_addr,
    .palette_sp0_data,
    .palette_sp1_addr,
    .palette_sp1_data,
    .palette_sp2_addr,
    .palette_sp2_data,
    .palette_sp3_addr,
    .palette_sp3_data,
    .palette_sp4_addr,
    .palette_sp4_data,
    .palette_sp5_addr,
    .palette_sp5_data,
    .palette_sp6_addr,
    .palette_sp6_data,
    .palette_sp7_addr,
    .palette_sp7_data,

    .inc_coarse_x,
    .inc_fine_y,
    .inc_oam_addr(dma_did_write),
    .reset_coarse_x,
    .reset_v,
    .set_vblank,
    .set_sprite_overflow,
    .reset_oam_addr,
    .set_sprite_zero_hit,

    .v_fine_y,
    .v_nt_sel,
    .v_coarse_y,
    .v_coarse_x,
    .fine_x,

    .PPUCTRL,
    .PPUSTATUS,
    .PPUMASK,
    .nmi_occurred,

    .oam_addr,

    .addressbus(reg_addressbus),
    .mem_rw_active(reg_addressbus_active),
    .mem_write_active(mem_write_active),
    .mem_write_data(data_write),
    .data_read(dataline)
);

assign nmi = PPUCTRL[7] & nmi_occurred;

// Memory
reg [7:0] primaryOAM [0:'hFF];
reg [7:0] secondaryOAM [0:'h1F];

integer i;
initial begin
    for(i = 0; i < 'hFF; i = i + 1) begin
        primaryOAM[i] = 8'b0;
    end
    for(i = 0; i < 'h1F; i = i + 1) begin
        secondaryOAM[i] = 8'hFF;
    end
end

reg [13:0] addressbus = 0;

assign internal_mem_addr = (reg_addressbus_active) ? reg_addressbus : addressbus;

assign dataline = (reg_addressbus_active && mem_write_active) ? data_write : internal_mem_din;

always @ (negedge clk) begin
    internal_mem_rw <= 1;
    if (reg_addressbus_active && mem_write_active) begin
        if (internal_mem_addr < 'h3f00) begin
            internal_mem_rw <= 0;
            internal_mem_dout <= dataline;
        end
    end
end

// Data loading

reg [7:0] sprite_pattern_d_lo [7:0];
reg [7:0] sprite_pattern_d_hi [7:0];
reg [7:0] sprite_attr [7:0];
reg [7:0] sprite_x_pos [7:0];
reg [2:0] curr_sprite_fine_y = 0;
reg [7:0] curr_sprite_nametable_byte = 0;
reg curr_sprite_invalid = 0;

reg [15:0] pattern_data_lo = 0;
reg [15:0] pattern_data_hi = 0;

reg [7:0] attribute_data_lo = 0;
reg [7:0] attribute_data_hi = 0;

reg [7:0] nametable_byte = 0;
reg [7:0] attribute_table_byte = 0;
reg [7:0] pattern_table_tile_lo = 0;
reg [7:0] pattern_table_tile_hi = 0;

reg attribute_latch_lo = 0;
reg attribute_latch_hi = 0;

// Sprites

reg [7:0] prim_read_latch;

reg [5:0] oam_n = 0;
reg [1:0] oam_m = 0;

reg [4:0] sec_oam_pos = 0;
reg [3:0] count_sprites = 0;
reg disable_sec_oam_write = 0;

reg first_sprite_is_sprite_0 = 0;

localparam [2:0]
    SE_READ_Y = 0,
    SE_COPY_SPR1 = 1,
    SE_COPY_SPR2 = 2,
    SE_COPY_SPR3 = 3,
    SE_TEST_OVERFLOW = 4,
    SE_IDLE = 5;

reg [2:0] sprite_eval_state = SE_IDLE;

// Video output related

reg [5:0] pixeldata = 'h23;

reg buf1UsedByPPU = 1;
wire line_buf_active;

wire [5:0] line_buf_out_1;
wire [5:0] line_buf_out_2;

wire [7:0] line_buf_addr_vga;
wire [7:0] line_buf_addr_ppu;

VGALineBuffer line_buf1(
    .clk_write(clk),
    .addr_write(line_buf_addr_ppu),
    .data_write(pixeldata),
    .we(buf1UsedByPPU && line_buf_active),

    .clk_read(clkVGA),
    .addr_read(line_buf_addr_vga),
    .data_read(line_buf_out_1)
);

VGALineBuffer line_buf2(
    .clk_write(clk),
    .addr_write(line_buf_addr_ppu),
    .data_write(pixeldata),
    .we(!buf1UsedByPPU && line_buf_active),

    .clk_read(clkVGA),
    .addr_read(line_buf_addr_vga),
    .data_read(line_buf_out_2)
);

reg [8:0] ppu_y = 0; // Goes up to 261
reg [8:0] ppu_x = 0; // Goes up to 340
reg [8:0] addr  = 0; // Address to store current pixel at

reg odd_frame = 0;

wire [3:0] fine_x_idx = {1'b0, fine_x};

// Actual pixel value calculation
assign palette_addr = {1'b0, attribute_data_hi[7 - fine_x], attribute_data_lo[7 - fine_x], pattern_data_hi[15 - fine_x_idx], pattern_data_lo[15 - fine_x_idx]};
wire [5:0] bg_pixel = palette_data;
wire bg_transparent = !PPUMASK[3] || (pattern_data_hi[15 - fine_x_idx] | pattern_data_lo[15 - fine_x_idx]) == 0;

assign palette_sp0_addr = {1'b1, sprite_attr[0][1:0], sprite_pattern_d_hi[0][7], sprite_pattern_d_lo[0][7]};
wire [5:0] sp0_pixel = palette_sp0_data;
wire sp0_transparent = (ppu_x < 3 || sprite_x_pos[0] > 0 || (sprite_pattern_d_hi[0][7] | sprite_pattern_d_lo[0][7]) == 0);

assign palette_sp1_addr = {1'b1, sprite_attr[1][1:0], sprite_pattern_d_hi[1][7], sprite_pattern_d_lo[1][7]};
wire [5:0] sp1_pixel = palette_sp1_data;
wire sp1_transparent = (ppu_x < 3 || sprite_x_pos[1] > 0 || (sprite_pattern_d_hi[1][7] | sprite_pattern_d_lo[1][7]) == 0);

assign palette_sp2_addr = {1'b1, sprite_attr[2][1:0], sprite_pattern_d_hi[2][7], sprite_pattern_d_lo[2][7]};
wire [5:0] sp2_pixel = palette_sp2_data;
wire sp2_transparent = (ppu_x < 3 || sprite_x_pos[2] > 0 || (sprite_pattern_d_hi[2][7] | sprite_pattern_d_lo[2][7]) == 0);

assign palette_sp3_addr = {1'b1, sprite_attr[3][1:0], sprite_pattern_d_hi[3][7], sprite_pattern_d_lo[3][7]};
wire [5:0] sp3_pixel = palette_sp3_data;
wire sp3_transparent = (ppu_x < 3 || sprite_x_pos[3] > 0 || (sprite_pattern_d_hi[3][7] | sprite_pattern_d_lo[3][7]) == 0);

assign palette_sp4_addr = {1'b1, sprite_attr[4][1:0], sprite_pattern_d_hi[4][7], sprite_pattern_d_lo[4][7]};
wire [5:0] sp4_pixel = palette_sp4_data;
wire sp4_transparent = (ppu_x < 3 || sprite_x_pos[4] > 0 || (sprite_pattern_d_hi[4][7] | sprite_pattern_d_lo[4][7]) == 0);

assign palette_sp5_addr = {1'b1, sprite_attr[5][1:0], sprite_pattern_d_hi[5][7], sprite_pattern_d_lo[5][7]};
wire [5:0] sp5_pixel = palette_sp5_data;
wire sp5_transparent = (ppu_x < 3 || sprite_x_pos[5] > 0 || (sprite_pattern_d_hi[5][7] | sprite_pattern_d_lo[5][7]) == 0);

assign palette_sp6_addr = {1'b1, sprite_attr[6][1:0], sprite_pattern_d_hi[6][7], sprite_pattern_d_lo[6][7]};
wire [5:0] sp6_pixel = palette_sp6_data;
wire sp6_transparent = (ppu_x < 3 || sprite_x_pos[6] > 0 || (sprite_pattern_d_hi[6][7] | sprite_pattern_d_lo[6][7]) == 0);

assign palette_sp7_addr = {1'b1, sprite_attr[7][1:0], sprite_pattern_d_hi[7][7], sprite_pattern_d_lo[7][7]};
wire [5:0] sp7_pixel = palette_sp7_data;
wire sp7_transparent = (ppu_x < 3 || sprite_x_pos[7] > 0 || (sprite_pattern_d_hi[7][7] | sprite_pattern_d_lo[7][7]) == 0);

wire [5:0] sprite_chosen_pixel = 
    (!sp0_transparent) ? sp0_pixel :
    (!sp1_transparent) ? sp1_pixel :
    (!sp2_transparent) ? sp2_pixel :
    (!sp3_transparent) ? sp3_pixel :
    (!sp4_transparent) ? sp4_pixel :
    (!sp5_transparent) ? sp5_pixel :
    (!sp6_transparent) ? sp6_pixel :
    (!sp7_transparent) ? sp7_pixel : 0;

wire sprite_priority =
    (!sp0_transparent) ? sprite_attr[0][5] :
    (!sp1_transparent) ? sprite_attr[1][5] :
    (!sp2_transparent) ? sprite_attr[2][5] :
    (!sp3_transparent) ? sprite_attr[3][5] :
    (!sp4_transparent) ? sprite_attr[4][5] :
    (!sp5_transparent) ? sprite_attr[5][5] :
    (!sp6_transparent) ? sprite_attr[6][5] :
    (!sp7_transparent) ? sprite_attr[7][5] : 0;

wire sprite_transparent = 
    !PPUMASK[4] ||
    (sp0_transparent & sp1_transparent &
    sp2_transparent & sp3_transparent &
    sp4_transparent & sp5_transparent &
    sp6_transparent & sp7_transparent);

wire [14:0] vram_addr = {v_fine_y, v_nt_sel, v_coarse_y, v_coarse_x};
wire render_disable = !(PPUMASK[3] || PPUMASK[4]);

wire [7:0] bit_inv_dataline = {dataline[0], dataline[1], dataline[2], dataline[3], dataline[4], dataline[5], dataline[6], dataline[7]};

integer spr_i;
always @ (posedge clk)
begin
    inc_coarse_x <= 0;
    inc_fine_y <= 0;
    reset_coarse_x <= 0;
    reset_v <= 0;
    set_vblank <= 0;
    set_sprite_zero_hit <= 0;

    if (rst) begin
        ppu_x <= 0;
        ppu_y <= 0;
        odd_frame <= 0;
        buf1UsedByPPU <= 1;
    end
    if (render_disable) begin
        pixeldata <= 'hD;
    end else begin
        // PPU logic
        if (ppu_y < 240 || (ppu_y == SCANLINE_COUNT - 1 && ppu_x >= 321)) begin


            if ((ppu_x >= 1 && ppu_x <= 256) || ppu_x >= 321) begin
                // Render

                if (bg_transparent & sprite_transparent)   pixeldata <= bg_color;
                if (bg_transparent & !sprite_transparent)  pixeldata <= sprite_chosen_pixel;
                if (!bg_transparent & sprite_transparent)  pixeldata <= bg_pixel;
                if (!bg_transparent & !sprite_transparent) begin
                    pixeldata <= (sprite_priority) ? bg_pixel : sprite_chosen_pixel;
                end

                // Sprite 0 hit
                if (first_sprite_is_sprite_0 && !bg_transparent && !sp0_transparent && PPUMASK[4]) set_sprite_zero_hit <= 1;

                // Read data
                case ((ppu_x - 1) & 7)
                    0: addressbus            <= {2'b10, vram_addr[11:0]}; // 0x2000 | addr;
                    1: nametable_byte        <= dataline;
                    2: addressbus            <= {2'b10, v_nt_sel, 4'b1111, v_coarse_y[4:2], v_coarse_x[4:2]}; // 0x23c0 | addr
                    3: attribute_table_byte  <= dataline;
                    4: addressbus            <= {1'd0, PPUCTRL[4], nametable_byte, 1'd0, v_fine_y};
                    5: pattern_table_tile_lo <= dataline;
                    6: addressbus            <= {1'd0, PPUCTRL[4], nametable_byte, 1'd1, v_fine_y};
                    7: begin
                        pattern_table_tile_hi <= dataline;
                        inc_coarse_x <= 1;
                    end
                endcase
            end

            if (ppu_x >= 257 && ppu_x <= 320) begin
                // Read data
                case ((ppu_x - 1) & 7)
                    0: addressbus                      <= {2'b10, vram_addr[11:0]}; // 0x2000 | addr;
                    1: ; //nametable_byte                <= dataline;
                    2: addressbus                      <= {2'b10, v_nt_sel, 4'b1111, v_coarse_y[4:2], v_coarse_x[4:2]}; // 0x23c0 | addr
                    3: ; //attribute_table_byte          <= dataline;
                    4: addressbus <= 
                        {
                            1'd0, PPUCTRL[3], curr_sprite_nametable_byte, 1'd0,
                            (sprite_attr[ppu_x[5:3]][7]) ? (3'h7 - curr_sprite_fine_y) : curr_sprite_fine_y
                        };
                    5: sprite_pattern_d_lo[ppu_x[5:3]] <= (curr_sprite_invalid) ? 8'h00 : ((sprite_attr[ppu_x[5:3]][6]) ? bit_inv_dataline : dataline);
                    6: addressbus <= 
                        {
                            1'd0, PPUCTRL[3], curr_sprite_nametable_byte, 1'd1,
                            (sprite_attr[ppu_x[5:3]][7]) ? (3'h7 - curr_sprite_fine_y) : curr_sprite_fine_y
                        };
                    7: sprite_pattern_d_hi[ppu_x[5:3] - 1] <= (curr_sprite_invalid) ? 8'h00 : ((sprite_attr[ppu_x[5:3] - 1][6]) ? bit_inv_dataline : dataline);
                endcase
            end

            if (ppu_x >= 2 && ppu_x <= 257 || ppu_x >= 322 && ppu_x <= 337) begin
                // Shift registers
                pattern_data_lo <= {pattern_data_lo[14:0], 1'b0};
                pattern_data_hi <= {pattern_data_hi[14:0], 1'b0};
                attribute_data_lo <= {attribute_data_lo[6:0], attribute_latch_lo};
                attribute_data_hi <= {attribute_data_hi[6:0], attribute_latch_hi};
            end

            if (ppu_x > 8 && (ppu_x & 7) == 1) begin
                // Load shifters
                pattern_data_lo <= {pattern_data_lo[14:8], pattern_table_tile_lo[7:0], 1'b0};
                pattern_data_hi <= {pattern_data_hi[14:8], pattern_table_tile_hi[7:0], 1'b0};
                attribute_latch_lo <= attribute_table_byte[{v_coarse_y[1], !v_coarse_x[1], 1'b0}];
                attribute_latch_hi <= attribute_table_byte[{v_coarse_y[1], !v_coarse_x[1], 1'b1}];
            end

            if (ppu_x == 256) begin
                inc_fine_y <= 1;
            end

            if (ppu_x == 257) begin
                reset_coarse_x <= 1;
            end
        end
    end

    if (!render_disable && ppu_y == SCANLINE_COUNT - 1 && ppu_x >= 280 && ppu_x <= 304) reset_v <= 1;

    if (
        ppu_x == CYCLE_COUNT - 1 ||
        (render_disable && (ppu_y == SCANLINE_COUNT - 1 && ppu_x == CYCLE_COUNT - 2 && odd_frame))
    ) begin
        ppu_x <= 0;
        addr <= 0;

        if (ppu_y == SCANLINE_COUNT - 1)
        begin
            ppu_y <= 0;
            buf1UsedByPPU <= 1;
            if (!render_disable) odd_frame <= !odd_frame;
        end else begin
            ppu_y <= ppu_y + 1;
            buf1UsedByPPU <= !buf1UsedByPPU;
        end
    end else begin
        ppu_x <= ppu_x + 1;
    end

    if (ppu_x <= 256)
    begin
        addr <= addr + 1;
    end

    if (ppu_x > 0 && ppu_x < 256) begin
        for (spr_i = 0; spr_i < 'h8; spr_i = spr_i + 1) begin
            if (sprite_x_pos[spr_i] != 0) begin
                sprite_x_pos[spr_i] <= sprite_x_pos[spr_i] - 1;
            end else begin
                sprite_pattern_d_hi[spr_i] <= {sprite_pattern_d_hi[spr_i][6:0], 1'b0};
                sprite_pattern_d_lo[spr_i] <= {sprite_pattern_d_lo[spr_i][6:0], 1'b0};
            end
        end
    end

    if (ppu_y == 241 && ppu_x == 1) begin
        set_vblank <= 1;
    end else if (ppu_y == SCANLINE_COUNT - 1 && ppu_x == 1) begin
        set_vblank <= 2;
        set_sprite_overflow <= 2;
    end else begin
        set_vblank <= 0;
    end

    dma_did_write <= 0;
    if (cpu_oam_dma_active) begin
        primaryOAM[oam_addr] <= cpu_din;
        dma_did_write <= 1;
    end


    // PPU sprite evaluation, OAM DMA
    if (!render_disable && ppu_y < 240) begin
        if ((ppu_x & 1) == 0) begin
            prim_read_latch <= primaryOAM[{oam_n, oam_m}];
        end
        if (ppu_x >= 1 && ppu_x <= 64 && (ppu_x & 1) == 1) begin
            secondaryOAM[sec_oam_pos] <= 8'hFF;
            sec_oam_pos <= sec_oam_pos + 1;
        end else if (ppu_x <= 256) begin
            case (sprite_eval_state)
                SE_READ_Y: begin
                    if ((ppu_x & 1) == 1) begin
                        if (!disable_sec_oam_write) begin
                            secondaryOAM[sec_oam_pos] <= prim_read_latch;
                            if (prim_read_latch <= ppu_y && prim_read_latch + 8 > ppu_y) begin
                                oam_m <= oam_m + 1;
                                sec_oam_pos <= sec_oam_pos + 1;
                                sprite_eval_state <= SE_COPY_SPR1;
                                if (oam_n == 0) first_sprite_is_sprite_0 <= 1;
                            end else begin
                                if (oam_n == 63) begin
                                    sprite_eval_state <= SE_IDLE;
                                end else begin
                                    oam_n <= oam_n + 1;
                                    sprite_eval_state <= SE_READ_Y;
                                    if (count_sprites == 8) begin
                                        disable_sec_oam_write <= 1;
                                        sprite_eval_state <= SE_TEST_OVERFLOW;
                                    end
                                    oam_m <= 0;
                                end
                            end
                        end
                    end
                end
                SE_COPY_SPR1: begin
                    if ((ppu_x & 1) == 1) begin
                        secondaryOAM[sec_oam_pos] <= prim_read_latch;
                        oam_m <= oam_m + 1;
                        sec_oam_pos <= sec_oam_pos + 1;
                        sprite_eval_state <= SE_COPY_SPR2;
                    end
                end
                SE_COPY_SPR2: begin
                    if ((ppu_x & 1) == 1) begin
                        secondaryOAM[sec_oam_pos] <= prim_read_latch;
                        oam_m <= oam_m + 1;
                        sec_oam_pos <= sec_oam_pos + 1;
                        sprite_eval_state <= SE_COPY_SPR3;
                    end
                end
                SE_COPY_SPR3: begin
                    if ((ppu_x & 1) == 1) begin
                        secondaryOAM[sec_oam_pos] <= prim_read_latch;
                        oam_m <= oam_m + 1;
                        sec_oam_pos <= sec_oam_pos + 1;
                        count_sprites <= count_sprites + 1;
                        if (oam_n == 63) begin
                            sprite_eval_state <= SE_IDLE;
                        end else begin
                            oam_n <= oam_n + 1;
                            sprite_eval_state <= SE_READ_Y;
                            if (count_sprites == 7) begin // will be 8
                                disable_sec_oam_write <= 1;
                                sprite_eval_state <= SE_TEST_OVERFLOW;
                            end
                            oam_m <= 0;
                        end
                    end
                end
                SE_TEST_OVERFLOW: begin
                    if (prim_read_latch <= ppu_y && prim_read_latch + 8 > ppu_y) begin
                        // sprite in range
                        set_sprite_overflow <= 1;
                        oam_n <= oam_n + 1;
                        sprite_eval_state <= SE_IDLE;
                    end else begin
                        // sprite not in range
                        if (oam_n == 63) sprite_eval_state <= SE_IDLE;
                        oam_n <= oam_n + 1;
                        oam_m <= oam_m + 1;
                        // don't change state otherwise
                    end
                end
                SE_IDLE: sec_oam_pos <= 0;
            endcase
        end else if (ppu_x <= 320) begin
            case ((ppu_x - 1) & 7)
                'h0: curr_sprite_fine_y <= ppu_y - secondaryOAM[sec_oam_pos];
                'h1: curr_sprite_nametable_byte <= secondaryOAM[sec_oam_pos];
                'h2: sprite_attr[sec_oam_pos[4:2]] <= secondaryOAM[sec_oam_pos];
                'h3: begin
                    sprite_x_pos[sec_oam_pos[4:2]] <= secondaryOAM[sec_oam_pos];

                    // TODO: breaks if places correctly at 'h0
                    curr_sprite_invalid <= (secondaryOAM[sec_oam_pos - 3] == 'hFF);
                end
            endcase
            if (((ppu_x - 1) & 7) < 4) sec_oam_pos <= sec_oam_pos + 1;
        end else begin
            sec_oam_pos <= 0;
            disable_sec_oam_write <= 0;
            sprite_eval_state <= SE_READ_Y;
            count_sprites <= 0;
            first_sprite_is_sprite_0 <= 0;
        end
        reset_oam_addr <= (ppu_x >= 257 && ppu_x <= 320);
        if (ppu_x == 63) {oam_n, oam_m} <= oam_addr;
    end
end

assign line_buf_addr_ppu = addr[7:0];

assign line_buf_active = (ppu_y <= 240);

reg vsync_toggle_clkMaster = 0;
always @ (posedge clk) begin
    vsync_toggle_clkMaster <= vsync_toggle_clkMaster ^ (ppu_y == 242 && ppu_x == 0); // at sc=241, cyc=0, VGA needs to draw one more scanline
end

reg [2:0] sync_vsync_clkVGA = 0;
always @ (posedge clkVGA) begin
    sync_vsync_clkVGA <= {sync_vsync_clkVGA[1:0], vsync_toggle_clkMaster};
end

wire ppu_v_sync = (sync_vsync_clkVGA[2] ^ sync_vsync_clkVGA[1]);

VideoOut video_out(
    .clk(clkVGA),
    .ppu_v_sync(ppu_v_sync),
    .addr(line_buf_addr_vga),
    .pixeldata((buf1UsedByPPU) ? line_buf_out_2 : line_buf_out_1),
    .hsync(hsync),
    .vsync(vsync),
    .red(red),
    .grn(grn),
    .blu(blu),
    .rst(rst)
);

endmodule

