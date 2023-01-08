`include "defs.svh"

module ppu_control(
    input  logic [8:0] x_i,
    output logic [8:0] x_o,
    input  logic [8:0] y_i,
    output logic [8:0] y_o,

    input rendering_enabled_i,
    
    input  odd_frame_i,
    output odd_frame_o,

    input  logic [14:0] vram_home_addr_i,
    input  logic [14:0] vram_addr_i,
    output logic [14:0] vram_addr_o
);

logic [8:0] x_next, y_next;
assign x_o = x_next;
assign y_o = y_next;

wire [2:0] curr_phase = x_i[2:0];

wire [2:0] fine_y_i = vram_addr_i[14:12];
wire [1:0] nametable_sel_i = vram_addr_i[11:10];
wire [4:0] coarse_y_i = vram_addr_i[9:5];
wire [4:0] coarse_x_i = vram_addr_i[4:0];

wire [2:0] fine_y_home = vram_home_addr_i[14:12];
wire [1:0] nametable_sel_home = vram_home_addr_i[11:10];
wire [4:0] coarse_y_home = vram_home_addr_i[9:5];
wire [4:0] coarse_x_home = vram_home_addr_i[4:0];

logic [2:0] fine_y_o;
logic [1:0] nametable_sel_o;
logic [4:0] coarse_x_o, coarse_y_o;

assign vram_addr_o = {fine_y_o, nametable_sel_o, coarse_y_o, coarse_x_o};

always_comb begin : xy_logic
    x_next = x_i + 1;
    y_next = y_i;
    odd_frame_o = odd_frame_i;
    if (x_i == 9'd340) begin
        x_next = '0;
        y_next = y_i + 1;
        if (y_i == 9'd261) begin
            y_next = '0;
            odd_frame_o = !odd_frame_i;
        end
    end
    if (rendering_enabled_i && odd_frame_i && x_i == 339 && y_i == 261) begin
        x_next = '0;
        y_next = '0;
        odd_frame_o = !odd_frame_i;
    end
end

always_comb begin : inc_hori_vert_logic
    fine_y_o = fine_y_i;
    nametable_sel_o = nametable_sel_i;
    coarse_y_o = coarse_y_i;
    coarse_x_o = coarse_x_i;

    if (y_i < 240 || y_i == 261) begin
        // Horizontal increase
        if (curr_phase == 7 && ((x_i != 0 && x_i < 257) || x_i > 320)) begin
            coarse_x_o = coarse_x_i + 1; // wraparound at 31 happens automatically
            if (coarse_x_i == 31) begin
                nametable_sel_o[0] = !nametable_sel_o[0];
            end
        end
        
        // Horizontal reset
        if (x_i == 256) begin
            coarse_x_o = coarse_x_home;
            nametable_sel_o[0] = nametable_sel_home[0];
        end

        // Vertical increase
        if (x_i == 255) begin
            fine_y_o = fine_y_i + 1;
            if (fine_y_i == 7) begin
                fine_y_o = '0;
                coarse_y_o = coarse_y_i + 1; // wraparound at 31 happens automatically
                if (coarse_y_i == 29) begin
                    coarse_y_o = '0;
                    nametable_sel_o[1] = !nametable_sel_o[1];
                end
            end
        end
        
        // Vertical reset
        if (y_i == 261 && x_i >= 280 && x_i <= 304) begin
            fine_y_o = fine_y_home;
            coarse_y_o = coarse_y_home;
            nametable_sel_o[1] = nametable_sel_home[1];
        end
    end
end

endmodule
