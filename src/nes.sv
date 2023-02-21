`include "defs.svh"

module nes (
    input logic clk,
    input logic rst_n,

    output logic [15:0] cpu_a_o,
    output logic  [7:0] cpu_d_o,
    input  logic  [7:0] cpu_d_i,
    output logic        cpu_rw_o,

    output logic [13:0] ppu_a_o,
    output logic  [7:0] ppu_d_o,
    input  logic  [7:0] ppu_d_i,
    output logic        ppu_rw_o,

    input logic vram_ce,
    input logic vram_a10,

    output logic [4:0] color_o
);

// Enable waveform output
initial begin
    $dumpfile("trace.fst");
    $dumpvars;
end

// TODO: internal RAM

logic clk_cpu, clk_ppu;
logic [1:0] count_ppu_clk;

assign clk_ppu = clk;
assign clk_cpu = (count_ppu_clk == 1 || count_ppu_clk == 2);

logic [7:0] ppu_cpu_bus_data_w;

logic nmi;

logic ppu_cpubus_enable;

logic cpu_ce_q;

logic [7:0] cpu_actual_data_r;
always_comb begin : cpu_memory_map_logic
    if (cpu_a_o >= 16'h2000 && cpu_a_o < 16'h4000) begin
        cpu_actual_data_r = ppu_cpu_bus_data_w;
        ppu_cpubus_enable = clk_cpu && !cpu_ce_q;
    end else begin
        cpu_actual_data_r = cpu_d_i;
        ppu_cpubus_enable = '0;
    end
end

always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        count_ppu_clk <= '0;
        cpu_ce_q <= '0;
    end else begin
        cpu_ce_q <= clk_cpu;
        count_ppu_clk <= count_ppu_clk + 1;
        if (count_ppu_clk == 2) count_ppu_clk <= 0;
    end
end

cpu6502 i_cpu6502(
    .clk(clk_cpu),
    .rst_n(rst_n),

    .bus_address_o(cpu_a_o),
    .bus_data_i(cpu_actual_data_r),
    .bus_data_o(cpu_d_o),
    .bus_rw_o(cpu_rw_o),

    .nmi_i(nmi)
);

ppu i_ppu(
    .clk(clk_ppu),
    .rst_n(rst_n),

    .ppubus_address_o(ppu_a_o),
    .ppubus_data_i(ppu_d_i),
    .ppubus_data_o(ppu_d_o),
    .ppubus_rw_o(ppu_rw_o),

    .vram_ce(vram_ce),
    .vram_a10(vram_a10),
    
    .cpubus_address_i(cpu_a_o[2:0]),
    .cpubus_data_i(cpu_d_o),
    .cpubus_data_o(ppu_cpu_bus_data_w),
    .cpubus_rw_i(cpu_rw_o),
    .cpubus_ce_i(ppu_cpubus_enable),

    .nmi_o(nmi),

    .color_o(color_o)
);

endmodule
