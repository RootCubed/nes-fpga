`include "defs.svh"

module ppu_mmregs(
    input logic clk,
    input logic rst_n,
    
    input logic [8:0] x_i,
    input logic [8:0] y_i,    

    input logic [2:0] addr_i,
    input logic [7:0] data_i,
    input logic we_i,
    input logic ce_i,
    output logic [7:0] data_o,

    output logic nmi_o,

    input logic [7:0] oam_data_i,
    input logic [7:0] oam_addr_i,
    output logic [7:0] oam_addr_o,
    output logic oam_addr_w_o,
    output logic [7:0] oam_data_o,
    output logic oam_data_w_o,

    input logic sprite_overflow_i,
    input logic sprite_0_hit_i,

    output logic spr_pattable_half_o,
    output logic bg_pattable_half_o,
    output logic bg_enable_o,
    output logic spr_enable_o,

    input logic [7:0] vram_data_i,
    output logic [7:0] vram_data_o,
    output logic vram_override_addr_o,
    output logic vram_we_o,

    input logic [14:0] vram_home_addr_i,
    output logic [14:0] vram_home_addr_o,
    output logic vram_home_addr_we_o,
    output logic reset_vram_to_home_o,
    output logic inc_vram_1_o,
    output logic inc_vram_32_o,

    output logic [2:0] fine_x_o,
    output logic fine_x_we_o
);

logic sprite_overflow, sprite_0_hit, vblank;
logic clear_vblank;
logic vram_inc;

logic second_write_q, first_write_d;

logic vram_inc_is_32_q, vram_inc_is_32_d;
logic spr_pattable_half_q, spr_pattable_half_d;
logic bg_pattable_half_q, bg_pattable_half_d;
logic spr_size_q, spr_size_d;
logic gen_nmi_q, gen_nmi_d;

logic bg_enable_q, bg_enable_d;
logic spr_enable_q, spr_enable_d;
assign bg_enable_o = bg_enable_q;
assign spr_enable_o = spr_enable_q;

logic [7:0] output_reg, next_output;
assign data_o = output_reg;

assign spr_pattable_half_o = spr_pattable_half_q;
assign bg_pattable_half_o = bg_pattable_half_q;

always_comb begin
    next_output = '0;
    first_write_d = second_write_q;
    vram_home_addr_o = vram_home_addr_i;
    vram_home_addr_we_o = '0;
    fine_x_we_o = '0;
    reset_vram_to_home_o = '0;
    clear_vblank = '0;
    vram_inc = '0;
    vram_we_o = '0;
    vram_override_addr_o = '0;

    vram_inc_is_32_d = vram_inc_is_32_q;
    spr_pattable_half_d = spr_pattable_half_q;
    bg_pattable_half_d = bg_pattable_half_q;
    spr_size_d = spr_size_q;
    gen_nmi_d = gen_nmi_q;
    bg_enable_d = bg_enable_q;
    spr_enable_d = spr_enable_q;

    oam_addr_o = '0;
    oam_addr_w_o = '0;
    oam_data_o = '0;
    oam_data_w_o = '0;
    
    if (ce_i && we_i) begin
        case (addr_i)
            0: begin // PPUCTRL
                vram_home_addr_o[11:10] = data_i[1:0];
                vram_home_addr_we_o = '1;
                vram_inc_is_32_d = data_i[2];
                spr_pattable_half_d = data_i[3];
                bg_pattable_half_d = data_i[4];
                spr_size_d = data_i[5];
                gen_nmi_d = data_i[7];
            end
            1: begin // PPUMASK
                bg_enable_d = data_i[3];
                spr_enable_d = data_i[4];
            end
            3: begin // OAMADDR
                oam_addr_o = data_i;
                oam_addr_w_o = 1'h1;
            end
            4: begin // OAMDATA
                oam_data_o = data_i;
                oam_data_w_o = 1'h1;
                oam_addr_o = oam_addr_i + 8'h1;
                oam_addr_w_o = 1'h1;
            end
            5: begin // PPUSCROLL
                if (!second_write_q) begin
                    vram_home_addr_o[4:0] = data_i[7:3];
                    fine_x_o = data_i[2:0];
                    fine_x_we_o = '1;
                end else begin
                    vram_home_addr_o[14:12] = data_i[2:0];
                    vram_home_addr_o[9:5] = data_i[7:3];
                end
                vram_home_addr_we_o = '1;
                first_write_d = !second_write_q;
            end
            6: begin // PPUADDR
                if (!second_write_q) begin
                    vram_home_addr_o[13:8] = data_i[5:0];
                    vram_home_addr_o[14] = '0;
                end else begin
                    vram_home_addr_o[7:0] = data_i;
                    reset_vram_to_home_o = '1;
                end
                vram_home_addr_we_o = '1;
                first_write_d = !second_write_q;
            end
            7: begin // PPUDATA
                vram_inc = '1;
                vram_data_o = data_i;
                vram_override_addr_o = '1;
                vram_we_o = '1;
            end
        endcase
    end else if (ce_i && !we_i) begin
        case (addr_i)
            2: begin // PPUSTATUS
                next_output = {vblank, sprite_0_hit, sprite_overflow, output_reg[4:0]};
                first_write_d = '0;
                clear_vblank = '1;
            end
            3: begin // OAMDATA
                next_output = oam_data_i;
                oam_addr_o = oam_addr_i + 8'h1;
                oam_addr_w_o = 1'h1;
            end
            7: begin // PPUDATA
                vram_inc = '1;
                next_output = vram_data_i;
                vram_override_addr_o = '1;
            end
        endcase
    end
end

always_comb begin : vram_inc_logic
    inc_vram_1_o = (vram_inc && !vram_inc_is_32_q);
    inc_vram_32_o = (vram_inc && vram_inc_is_32_q);
end

always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        sprite_overflow <= '0;
        sprite_0_hit <= '0;
        vblank <= '0;
        second_write_q <= '0;
        vram_inc_is_32_q <= '0;
        spr_pattable_half_q <= '0;
        bg_pattable_half_q <= '0;
        spr_size_q <= '0;
        gen_nmi_q <= '0;
        output_reg <= '0;
        bg_enable_q <= '0;
        spr_enable_q <= '0;
    end else begin
        second_write_q <= first_write_d;
        vram_inc_is_32_q <= vram_inc_is_32_d;
        spr_pattable_half_q <= spr_pattable_half_d;
        bg_pattable_half_q <= bg_pattable_half_d;
        spr_size_q <= spr_size_d;
        gen_nmi_q <= gen_nmi_d;
        bg_enable_q <= bg_enable_d;
        spr_enable_q <= spr_enable_d;
        if (y_i == 261 && x_i == 0) begin
            sprite_overflow <= '0;
            sprite_0_hit <= '0;
            vblank <= '0;
        end else begin
            sprite_overflow <= (sprite_overflow || sprite_overflow_i);
            sprite_0_hit <= (sprite_0_hit || sprite_0_hit_i);
            vblank <= !clear_vblank && (vblank || (y_i == 241 && x_i == 0));
        end
        nmi_o <= gen_nmi_q && vblank;

        if (ce_i && !we_i) begin
            output_reg <= next_output;
        end else if (ce_i && we_i) begin
            output_reg <= data_i;
        end
    end
end

endmodule
