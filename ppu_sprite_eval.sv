`include "defs.svh"

module ppu_sprite_eval(
    input logic clk,
    input logic rst_n,
    
    input logic [8:0] x_i,
    input logic [8:0] y_i,

    input logic spr_enable_i,

    output logic [7:0] oam_addr_o,
    input  logic [7:0] oam_data_i,

    input logic [7:0] new_oam_addr_i,
    input logic       new_oam_addr_w_i,

    input  logic [4:0] sec_oam_addr_i,
    output logic [7:0] sec_oam_data_o,

    output logic overflow_o,
    output logic slot_0_is_spr_0_o
);

typedef enum { 
    SprEvalInit,
    SprEvalCopyY,
    SprEvalCopySprData,
    SprEvalOverflowCheck,
    SprEvalDone
} sprite_eval_state_e;

logic [7:0] sec_oam [0:31];
logic [4:0] sec_oam_addr_q, sec_oam_addr_d;
assign sec_oam_data_o = sec_oam[sec_oam_addr_i];

logic sec_oam_we;

sprite_eval_state_e state_q, state_d, next_state;
assign state_d = next_state;

logic [2:0] num_found_sprites_q, num_found_sprites_d;

logic overflow_flag_q, overflow_flag_d;
assign overflow_o = overflow_flag_q;

logic slot_0_is_spr_0_q, slot_0_is_spr_0_d;
assign slot_0_is_spr_0_o = slot_0_is_spr_0_q;

logic [5:0] n_q, n_d;
logic [1:0] m_q, m_d;

always_comb begin : sprite_eval_logic
    oam_addr_o = {n_q, m_q};
    overflow_flag_d = overflow_flag_q;

    n_d = n_q;
    m_d = m_q;
    sec_oam_addr_d = sec_oam_addr_q;
    num_found_sprites_d = num_found_sprites_q;
    slot_0_is_spr_0_d = slot_0_is_spr_0_q;

    case (state_q)
        SprEvalInit: begin
            next_state = (x_i < 64) ? SprEvalInit : SprEvalCopyY;
            sec_oam_addr_d = sec_oam_addr_q + 1;
            sec_oam_we = '1;
            num_found_sprites_d = '0;
            overflow_flag_d = '0;
            n_d = '0;
            m_d = '0;
            slot_0_is_spr_0_d = '0;
        end
        SprEvalCopyY: begin
            sec_oam_we = '1;
            if (y_i[7:0] >= oam_data_i && y_i[7:0] < oam_data_i + 8) begin
                next_state = SprEvalCopySprData;
                sec_oam_addr_d = sec_oam_addr_q + 1;
                m_d = m_q + 1;
            end else begin
                if (n_q == 63) begin
                    next_state = SprEvalDone;
                end else begin
                    next_state = SprEvalCopyY;
                end
                n_d = n_q + 1;
            end
        end
        SprEvalCopySprData: begin
            sec_oam_addr_d = sec_oam_addr_q + 1;
            sec_oam_we = '1;
            if (n_q == 0) begin
                slot_0_is_spr_0_d = '1;
            end
            if (m_q == 3) begin
                if (n_q == 63) begin
                    next_state = SprEvalDone;
                end else if (num_found_sprites_d == 7) begin
                    next_state = SprEvalOverflowCheck;
                end else begin
                    next_state = SprEvalCopyY;
                end
                n_d = n_q + 1;
                num_found_sprites_d = num_found_sprites_q + 1;
            end else begin
                next_state = SprEvalCopySprData;
            end
            m_d = m_q + 1;
        end
        SprEvalOverflowCheck: begin
            sec_oam_we = '0;
            next_state = SprEvalOverflowCheck;
            if (y_i[7:0] >= oam_data_i && y_i[7:0] < oam_data_i + 8) begin
                overflow_flag_d = '1;
                m_d = m_q + 3;
                if (m_d != 0) begin
                    n_d = n_q + 1;
                    if (n_q == 63) next_state = SprEvalDone;
                end
            end else begin
                m_d = m_q + 1; // PPU sprite evaluation bug
                n_d = n_q + 1;
                if (n_q == 63) next_state = SprEvalDone;
            end
        end
        SprEvalDone: begin
            sec_oam_we = '0;
            sec_oam_addr_d = '0;
            if (x_i == 0) next_state = SprEvalInit;
        end
        default: ;
    endcase
end

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        state_q <= SprEvalDone;
        sec_oam <= '{default:0};
        n_q <= '0;
        m_q <= '0;
        num_found_sprites_q <= '0;
        overflow_flag_q <= '0;
        slot_0_is_spr_0_q <= '0;
    end else begin
        if (new_oam_addr_w_i) begin
            n_q <= new_oam_addr_i[7:2];
            m_q <= new_oam_addr_i[1:0];
        end else begin
            if (spr_enable_i && x_i[0] == 0 && y_i < 240) begin
                if (sec_oam_we) sec_oam[sec_oam_addr_q] <= (x_i < 65) ? 8'hFF : oam_data_i;
                n_q <= n_d;
                m_q <= m_d;
                sec_oam_addr_q <= sec_oam_addr_d;
                state_q <= state_d;
                num_found_sprites_q <= num_found_sprites_d;
                overflow_flag_q <= overflow_flag_d;
                slot_0_is_spr_0_q <= slot_0_is_spr_0_d;
            end
        end
    end
end

endmodule
