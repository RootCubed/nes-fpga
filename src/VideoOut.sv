`timescale 1ns / 1ps

// VGA output module (Resolution 640x480 @ 60Hz).

module VideoOut(
    input clk,
    input ppu_v_sync,
    output [7:0] addr,
    input [5:0] pixeldata,
    input rst,
    output hsync,
    output vsync,
    output [3:0] red,
    output [3:0] grn,
    output [3:0] blu
);

reg [9:0] hcount;
reg [9:0] vcount;

// used for duplicating lines
reg isSecondLine;

// Horizontal timings
parameter H_ACT  = 640; // active pixels
parameter H_FPO  = 16;  // front porch
parameter H_SYNC = 96;  // sync
parameter H_BPO  = 48;  // back porch

// Vertical timings
parameter V_ACT  = 480; // active pixels
parameter V_FPO  = 10;  // front porch
parameter V_SYNC = 2;   // sync
parameter V_BPO  = 32;  // back porch

// We start on the second-to-last scanline so the PPU has time to write the first scanline to the buffer
parameter INITIAL_SCANLINE = V_BPO + V_ACT + V_FPO + V_SYNC - 2;

localparam [5:0] BORDER_COLOR = 'h0C; // dark cyan

initial hcount = 0;
initial vcount = INITIAL_SCANLINE;
initial isSecondLine = 0;

assign hsync = ~(hcount >= H_ACT + H_FPO && hcount < H_ACT + H_FPO + H_SYNC);
assign vsync = ~(vcount >= V_ACT + V_FPO && vcount < V_ACT + V_FPO + V_SYNC);

reg del_ppu_v_sync = 0;

always @ (posedge clk)
begin
    if (rst) begin
        hcount <= 0;
        vcount <= INITIAL_SCANLINE;
        isSecondLine <= 0;
    end

    // TODO: We only re-sync the VGA output to the PPU once every frame.
    // This causes minor graphical issues because of timing issues.
    if (hcount == H_ACT + H_FPO + H_SYNC + H_BPO - 1)
    begin
        isSecondLine <= !isSecondLine;
        hcount <= 0;
        if (vcount == V_ACT + V_FPO + V_SYNC + V_BPO - 1) begin
            vcount <= 0;
        end else begin
            vcount <= vcount + 1;
        end
    end else begin
        hcount <= hcount + 1;
    end

    del_ppu_v_sync <= ppu_v_sync;
    if (ppu_v_sync && ~del_ppu_v_sync)
    begin
        vcount <= V_ACT + 2; // Since sync happens at scanline 241, one line after last drawn scanline
        hcount <= 0;
        isSecondLine <= 0;
    end
end

wire render_enable = (vcount < V_ACT && hcount < H_ACT);

// Halving hcount to duplicate pixels horizontally
assign addr = hcount[8:1] - 8'd32;

// We want to draw the 256 pixels the PPU outputs to the center of the screen
wire render_border = (hcount < 32 * 2 || hcount >= H_ACT - 32 * 2);

wire [5:0] palette_color = render_border ? BORDER_COLOR : pixeldata;

// NES Color Palette
// Source: https://wiki.nesdev.org/w/index.php/PPU_palettes#2C02

reg [23:0] rgb;
always @ (palette_color)
begin
    case (palette_color)
        'h00: rgb = 'h54_54_54;
        'h01: rgb = 'h00_1e_74;
        'h02: rgb = 'h08_10_90;
        'h03: rgb = 'h30_00_88;
        'h04: rgb = 'h44_00_64;
        'h05: rgb = 'h5c_00_30;
        'h06: rgb = 'h54_04_00;
        'h07: rgb = 'h3c_18_00;
        'h08: rgb = 'h20_2a_00;
        'h09: rgb = 'h08_3a_00;
        'h0a: rgb = 'h00_40_00;
        'h0b: rgb = 'h00_3c_00;
        'h0c: rgb = 'h00_32_3c;
        'h0d: rgb = 'h00_00_00;
        'h0e: rgb = 'h00_00_00;
        'h0f: rgb = 'h00_00_00;
        'h10: rgb = 'h98_96_98;
        'h11: rgb = 'h08_4c_c4;
        'h12: rgb = 'h30_32_ec;
        'h13: rgb = 'h5c_1e_e4;
        'h14: rgb = 'h88_14_b0;
        'h15: rgb = 'ha0_14_64;
        'h16: rgb = 'h98_22_20;
        'h17: rgb = 'h78_3c_00;
        'h18: rgb = 'h54_5a_00;
        'h19: rgb = 'h28_72_00;
        'h1a: rgb = 'h08_7c_00;
        'h1b: rgb = 'h00_76_28;
        'h1c: rgb = 'h00_66_78;
        'h1d: rgb = 'h00_00_00;
        'h1e: rgb = 'h00_00_00;
        'h1f: rgb = 'h00_00_00;
        'h20: rgb = 'hec_ee_ec;
        'h21: rgb = 'h4c_9a_ec;
        'h22: rgb = 'h78_7c_ec;
        'h23: rgb = 'hb0_62_ec;
        'h24: rgb = 'he4_54_ec;
        'h25: rgb = 'hec_58_b4;
        'h26: rgb = 'hec_6a_64;
        'h27: rgb = 'hd4_88_20;
        'h28: rgb = 'ha0_aa_00;
        'h29: rgb = 'h74_c4_00;
        'h2a: rgb = 'h4c_d0_20;
        'h2b: rgb = 'h38_cc_6c;
        'h2c: rgb = 'h38_b4_cc;
        'h2d: rgb = 'h3c_3c_3c;
        'h2e: rgb = 'h00_00_00;
        'h2f: rgb = 'h00_00_00;
        'h30: rgb = 'hec_ee_ec;
        'h31: rgb = 'ha8_cc_ec;
        'h32: rgb = 'hbc_bc_ec;
        'h33: rgb = 'hd4_b2_ec;
        'h34: rgb = 'hec_ae_ec;
        'h35: rgb = 'hec_ae_d4;
        'h36: rgb = 'hec_b4_b0;
        'h37: rgb = 'he4_c4_90;
        'h38: rgb = 'hcc_d2_78;
        'h39: rgb = 'hb4_de_78;
        'h3a: rgb = 'ha8_e2_90;
        'h3b: rgb = 'h98_e2_b4;
        'h3c: rgb = 'ha0_d6_e4;
        'h3d: rgb = 'ha0_a2_a0;
        'h3e: rgb = 'h00_00_00;
        'h3f: rgb = 'h00_00_00;
        default: rgb = 'h00_00_00;
    endcase
end

assign red = render_enable ? rgb[23:20] : 4'b0;
assign grn = render_enable ? rgb[15:12] : 4'b0;
assign blu = render_enable ? rgb[ 7: 4] : 4'b0;

endmodule
