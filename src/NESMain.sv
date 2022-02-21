`timescale 1ns / 1ps

// Module that represents the internals of the NES console.

module NESMain(
    input clkMaster,
    input clkVGA,
    output [11:0] rgb_out,
    output hsync,
    output vsync,
    input rst,
    input [7:0] ctrl1
);

wire clkCPU, clkData, clkPPU;
ClockScale clock_scale(
    .clk_in(clkMaster),
    .clk_cpu(clkCPU),
    .clk_data(clkData),
    .clk_ppu(clkPPU)
);

reg [7:0] wram [0:'h1FFF];
reg [7:0] vram [0:'h1FFF];

integer i;
initial begin
    for(i = 0; i < 'h2000; i = i + 1) begin
        wram[i] = 8'b0;
        vram[i] = 8'b0;
    end
end

wire [15:0] cpu_addr;

wire [14:0] addr_cpu;
wire  [7:0] data_cpu;
wire [12:0] addr_ppu;
wire  [7:0] data_ppu;
wire [ 7:0] ppu_internal_data_out;
wire        ppu_internal_rw;
    
Cartridge cart(
    .addr_cpu, .data_cpu,
    .addr_ppu, .data_ppu,
    .data_ppu_write(ppu_internal_data_out),
    .data_ppu_rw(ppu_internal_rw),
    .clk(clkMaster)
);

wire cpu_rw;

wire [7:0] cpu_din, cpu_dout;
wire [7:0] ppu_din, ppu_dout;

wire [13:0] ppu_internal_addr;
wire [ 7:0] ppu_internal_data;

assign addr_cpu = cpu_addr[14:0];
assign addr_ppu = ppu_internal_addr[12:0];

wire [4:0] mmregs_addr;
wire [7:0] mmregs_din, mmregs_dout;

assign mmregs_addr = cpu_addr[4:0];
assign mmregs_din = cpu_dout;

wire activate_dma;
wire dma_active;
wire dma_write;

MemMapRegs mem_map_regs(
    .addr(mmregs_addr),
    .data_in(mmregs_din),
    .data_out(mmregs_dout),
    .is_active(cpu_addr >= 'h4000 && cpu_addr < 'h4020),
    .is_read(cpu_rw),
    .controller1(ctrl1),
    .controller2(8'b0),
    .activate_dma,
    .clk(clkData)
);

reg [7:0] wram_data = 0;

assign cpu_din =
    (cpu_addr < 'h2000) ? wram_data :
    (cpu_addr < 'h4000) ? ppu_dout :
    (cpu_addr < 'h4020) ? mmregs_dout :
    (cpu_addr >= 'h8000) ? data_cpu : 0;

reg [7:0] vram_data = 0;

assign ppu_internal_data = (ppu_internal_addr < 'h2000) ? data_ppu : vram_data;

assign ppu_din = cpu_dout;

reg del_cpu_rw = 1;
reg del_ppu_internal_rw = 1;

always @ (negedge clkMaster) begin
    del_cpu_rw <= cpu_rw;
    if (!cpu_rw & ~del_cpu_rw) begin
        if (cpu_addr < 'h2000) begin
            wram[cpu_addr[12:0]] <= cpu_dout;
        end
    end else begin
        wram_data <= wram[cpu_addr[12:0]];
    end
    // TODO: mirroring
    del_ppu_internal_rw <= ppu_internal_rw;
    if (ppu_internal_addr >= 'h2000) begin
        if (!ppu_internal_rw & ~del_ppu_internal_rw) begin
            vram[ppu_internal_addr[10:0]] <= ppu_internal_data_out;
        end else begin
            vram_data <= vram[ppu_internal_addr[10:0]];
        end
    end
end

wire nmi_sig;

PPU ppu(
    .master_clk(clkMaster),
    .clk(clkPPU),
    .clkData(clkData),
    .clkVGA(clkVGA),
    .internal_mem_addr(ppu_internal_addr),
    .internal_mem_din(ppu_internal_data),
    .internal_mem_dout(ppu_internal_data_out),
    .internal_mem_rw(ppu_internal_rw),
    .cpu_a(cpu_addr[2:0]),
    .cpu_din(ppu_din),
    .cpu_dout(ppu_dout),
    .cpu_rw_active(cpu_addr >= 'h2000 && cpu_addr < 'h4000),
    .cpu_rw(cpu_rw),

    .cpu_oam_dma_active(dma_active && dma_write),

    .nmi(nmi_sig),
    .rst(rst),
    .hsync(hsync),
    .vsync(vsync),
    .red(rgb_out[11:8]),
    .grn(rgb_out[ 7:4]),
    .blu(rgb_out[ 3:0])
);

CPU cpu(
    .phi0(clkCPU),
    .addr(cpu_addr),
    .data_in(cpu_din),
    .data_out(cpu_dout),
    .is_read(cpu_rw),
    .rst(rst),
    .nmi(nmi_sig),
    .activate_dma,
    .dma_active,
    .dma_write
);

endmodule
